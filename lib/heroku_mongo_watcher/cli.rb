require 'heroku_mongo_watcher'
require 'heroku_mongo_watcher/configuration'
require 'heroku_mongo_watcher/mailer'
require 'heroku_mongo_watcher/data_row'
require 'trollop'

#http://stackoverflow.com/a/9117903/192791
require 'net/smtp'
Net.instance_eval {remove_const :SMTPSession} if defined?(Net::SMTPSession)

require 'net/pop'
Net::POP.instance_eval {remove_const :Revision} if defined?(Net::POP::Revision)
Net.instance_eval {remove_const :POP} if defined?(Net::POP)
Net.instance_eval {remove_const :POPSession} if defined?(Net::POPSession)
Net.instance_eval {remove_const :POP3Session} if defined?(Net::POP3Session)
Net.instance_eval {remove_const :APOPSession} if defined?(Net::APOPSession)

require 'tlsmail'

class HerokuMongoWatcher::CLI

  def self.config
    HerokuMongoWatcher::Configuration.instance.config
  end

  def self.mailer
    HerokuMongoWatcher::Mailer.instance
  end

  def self.watch
    Thread.abort_on_exception = true

    # lock warnings flags
    @lock_critical_notified = false
    @lock_warning_notified = false

    # average response time warning flags
    @art_critical_notified = false
    @art_warning_notified = false

    @current_row = HerokuMongoWatcher::DataRow.new
    @last_row = HerokuMongoWatcher::DataRow.new

    @mutex = Mutex.new

    # Let people know that its on, and confirm emails are being received
    mailer.notify(@current_row,"Mongo Watcher enabled!")

    # Call Tails heroku logs updates counts
    heroku_watcher = Thread.new('heroku_logs') do

      cmd_string = "heroku logs --tail --app #{config[:heroku_appname]}"
      cmd_string = cmd_string + " --account #{config[:heroku_account]}" if config[:heroku_account] && config[:heroku_account].length > 0
      IO.popen(cmd_string) do |f|
        while line = f.gets
          @mutex.synchronize do
            @current_row.process_heroku_router_line(line) if line.include? 'heroku[router]'
            @current_row.process_heroku_web_line(line) if line.include? 'app[web'
          end
        end
      end
    end

    # Call Heroku PS to check the number of up dynos
    heroku_ps = Thread.new('heroku_ps') do
      while true do
        dynos = 0
        cmd_string = "heroku ps --app #{config[:heroku_appname]}"
        cmd_string = cmd_string + " --account #{config[:heroku_account]}" if config[:heroku_account] && config[:heroku_account].length > 0
        IO.popen(cmd_string) do |p|
          while line = p.gets
            dynos += 1 if line =~ /^web/ && line.split(' ')[1] == 'up'
          end
        end
        @mutex.synchronize { @current_row.dynos = dynos }
        sleep(30)
      end
    end


    HerokuMongoWatcher::DataRow.print_header

    IO.popen("mongostat --rowcount 0 #{config[:interval]} --host #{config[:mongo_host]} --username #{config[:mongo_username]} --password #{config[:mongo_password]} --noheaders") do |f|
      while line = f.gets
        next unless line =~ /^/ && !(line =~ /^connected/)
        @mutex.synchronize do
          @current_row.process_mongo_line(line)

          @current_row.print_row

          check_and_notify

          @last_row = @current_row
          @current_row = HerokuMongoWatcher::DataRow.new
          @current_row.dynos = @last_row.dynos

        end
      end
    end

    heroku_watcher.join
    heroku_ps.join

  end

  def self.check_and_notify
    check_and_notify_locks
    check_and_notify_response_time
  end

  protected

  def self.check_and_notify_locks
    l = Float(@current_row.lock)
    if l > 90
      mailer.notify(@current_row, '[CRITICAL] Locks above 90%') unless @lock_critical_notified
    elsif l > 70
      mailer.notify(@current_row, '[WARNING] Locks above 70%') unless @lock_warning_notified
    elsif l < 50
      if @lock_warning_notified || @lock_critical_notified
        mailer.notify(@current_row, '[Resolved] locks below 50%')
        @lock_warning_notified = false
        @lock_critical_notified = false
      end

    end
  end

  def self.check_and_notify_response_time
    return unless @current_row.total_requests > 200
    if @current_row.average_response_time > 10_000 || @current_row.error_rate > 4
      mailer.notify "[SEVERE WARNING] Application not healthy | [#{@current_row.total_requests} rpm,#{@current_row.average_response_time} art]" unless @art_critical_notified
      @art_critical_notified = true
    elsif @current_row.average_response_time > 500 || @current_row.error_rate > 1 || @current_row.total_requests > 30_000
      mailer.notify "[WARNING] Application heating up | [#{@current_row.total_requests} rpm,#{@current_row.average_response_time} art]" unless @art_warning_notified
      @art_warning_notified = true
    elsif @current_row.average_response_time < 300 && @current_row.total_requests < 25_000
      if @art_warning_notified || @art_critical_notified
        mailer.notify "[RESOLVED] | [#{@current_row.total_requests} rpm,#{@current_row.average_response_time} art]"
        @art_warning_notified = false
        @art_critical_notified = false
      end
    end
  end

end
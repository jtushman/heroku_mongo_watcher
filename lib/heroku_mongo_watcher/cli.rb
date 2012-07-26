require 'heroku'
require 'heroku_mongo_watcher'
require 'heroku_mongo_watcher/configuration'
require 'heroku_mongo_watcher/mailer'
require 'heroku_mongo_watcher/data_row'

class HerokuMongoWatcher::CLI

  def self.config
    HerokuMongoWatcher::Configuration.instance.config
  end

  def self.mailer
    HerokuMongoWatcher::Mailer.instance
  end

  def self.heroku
    @heroku || Heroku::Client.new(config[:heroku_username],config[:heroku_password])
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

      heroku.read_logs(config[:heroku_appname],['tail=1']) do |line|
        @mutex.synchronize do
          @current_row.process_heroku_router_line(line) if line.include? 'heroku[router]'
          @current_row.process_heroku_web_line(line) if line.include? 'app[web'
        end
      end

    end

    # Call Heroku PS to check the number of up dynos
    heroku_ps = Thread.new('heroku_ps') do
      while true do
        results = heroku.ps(config[:heroku_appname])
        dynos = results.select{|ps| ps['process'] =~ /^web./ && ps['state'] == 'up'}.count

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

  rescue Interrupt
    puts "\nexiting ..."
  end

  def self.check_and_notify
    check_and_notify_locks
    check_and_notify_response_time
  end

  protected

  def self.check_and_notify_locks
    l = Float(@current_row.locked)
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
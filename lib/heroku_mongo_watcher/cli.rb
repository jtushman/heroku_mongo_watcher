require 'heroku_mongo_watcher/configuration'
require 'term/ansicolor'

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

  extend HerokuMongoWatcher::Configuration

  def self.watch(*args)
    f = File.join(File.expand_path('~'),'.watcher')
    configure_with(f)

    # lock warnings flags
    @lock_critical_notified = false
    @lock_warning_notified = false

    # average response time warning flags
    @art_critical_notified = false
    @art_warning_notified = false

    # memos
    @total_lines = 0
    @total_service = 0
    @total_wait = 0
    @total_queue = 0
    @total_router_errors = 0
    @total_web_errors = 0
    @max_service = 0
    @dynos = 0
    @slowest_request = nil
    @errors = {}

    @mutex = Mutex.new

    # Call Tails heroku logs updates counts
    heroku_watcher = Thread.new('heroku_logs') do
      IO.popen("heroku logs --tail --app #{config[:heroku_appname]} --account #{config[:heroku_account]}") do |f|
        while line = f.gets
          process_heroku_router_line(line) if line.include? 'heroku[router]'
          process_heroku_web_line(line) if line.include? 'app[web'
        end
      end
    end

    # Call Heroku PS to check the number of up dynos
    heroku_ps = Thread.new('heroku_ps') do
      while true do
        dynos = 0
        IO.popen("heroku ps --app #{config[:heroku_appname]} --account #{config[:heroku_account]}") do |p|
          while line = p.gets
            dynos += 1 if line =~ /^web/ && line.split(' ')[1] == 'up'
          end
        end
        @mutex.synchronize { @dynos = dynos }
        sleep(30)
      end
    end

    puts
    puts "|<---- heroku stats ------------------------------------------------------------>|<----mongo stats ------------------------------------------------------->|"
    puts "dyno reqs       art    max    r_err w_err   wait  queue slowest                  | insert  query  update  faults locked qr|qw  netIn  netOut    time       |"

    IO.popen("mongostat --rowcount 0 #{config[:interval]} --host #{config[:mongo_host]} --username #{config[:mongo_username]} --password #{config[:mongo_password]} --noheaders") do |f|
      while line = f.gets
        process_mongo_line(line) if line =~ /^/ && !(line =~ /^connected/)
      end
    end

    heroku_watcher.join
    heroku_ps.join

  end

  protected

  def self.process_mongo_line(line)
    items = line.split

    inserts = items[0]
    query = items[1]
    update = items[2]
    delete = items[3]
    getmore = items[4]
    command = items[5]
    flushes = items[6]
    mapped = items[7]
    vsize = items[8]
    res = items[9]
    faults = items[10]
    locked = items[11]
    idx_miss = items[12]
    qrw = items[13]
    arw = items[14]
    netIn = items[15]
    netOut = items[16]
    conn = items[17]
    set = items[18]
    repl = items[19]
    time = items[20]

    @mutex.synchronize do
      art = average_response_time
      err = @total_router_errors
      average_wait = @total_lines > 0 ? @total_wait / @total_lines : 'N/A'
      average_queue = @total_lines > 0 ? @total_queue / @total_lines : 'N/A'

      print_errors

      color_print @dynos, length: 4
      color_print @total_lines
      color_print art, warning: 1000, critical: 10_000, bold: true
      color_print @max_service, warning: 10_000, critical: 20_000
      color_print err, warning: 1, critical: 10
      color_print @total_web_errors, warning: 1, critical: 10
      color_print average_wait, warning: 10, critical: 100
      color_print average_queue, warning: 10, critical: 100
      color_print @slowest_request.slice(0,25), length: 28
      print '|'
      color_print inserts
      color_print query
      color_print update
      color_print faults
      color_print locked, bold: true, warning: 70, critical: 90
      color_print qrw
      color_print netIn
      color_print netOut
      color_print time, length: 10
      printf "\n"

      check_and_notify_locks(locked)
      check_and_notify_response_time(art, @total_lines)

      reset_memos

    end


  end

  def self.average_response_time
    @total_lines > 0 ? @total_service / @total_lines : 'N/A'
  end

  def self.print_errors
    if config[:print_errors] &&@errors && @errors.keys && @errors.keys.length > 0
      @errors.each do |error,count|
        puts "\t\t[#{count}] #{error}"
      end
    end
  end

  def self.process_heroku_web_line(line)
    # Only care about errors
    error_messages = config[:error_messages]

    if error_messages.any? { |mes| line.include? mes }
      items = line.split
      time = items[0]
      process = items[1]
      clean_line = line.sub(time,'').sub(process,'').strip
      @mutex.synchronize do
        @total_web_errors += 1
        if @errors.has_key? clean_line
          @errors[clean_line] = @errors[clean_line] + 1
        else
          @errors[clean_line] = 1
        end
      end
    end



  end

  def self.process_heroku_router_line(line)
    # 2012-07-05T20:24:10+00:00 heroku[router]: GET myapp.com/pxl/4fdbc97dc6b36c0030001160?value=1 dyno=web.14 queue=0 wait=0ms service=8ms status=200 bytes=35

    # or if error

    #2012-07-05T20:17:12+00:00 heroku[router]: Error H12 (Request timeout) -> GET myapp.com/crossdomain.xml dyno=web.4 queue= wait= service=30000ms status=503 bytes=0

    items = line.split

    if line =~ /Error/
      @mutex.synchronize { @total_router_errors += 1 }
    else


      time = items[0]
      process = items[1]
      http_type = items[2]
      url = items[3]
      dyno = items[4].split('=').last if items[4]
      queue = items[5].split('=').last.sub('ms', '') if items[5]
      wait = items[6].split('=').last.sub('ms', '') if items[6]
      service = items[7].split('=').last.sub('ms', '') if items[7]
      status = items[8].split('=').last if items[8]
      bytes = items[9].split('=').last if items[9]

      if is_number?(service) && is_number?(wait) && is_number?(queue)
        @mutex.synchronize do
          @total_lines +=1
          @total_service += Integer(service) if service
          @total_wait += Integer(wait) if wait
          @total_queue += Integer(queue) if queue
          if Integer(service) > @max_service
            @max_service = Integer(service)
            @slowest_request = URI('http://' + url).path
          end
        end
      end

    end

  end

  def self.reset_memos
    @total_service = @total_lines = @total_wait = @total_queue = @total_router_errors = @total_web_errors = @max_service = 0
    @errors = {}
  end

  def self.check_and_notify_locks(locked)
    l = Float(locked)
    if l > 90
      notify '[CRITICAL] Locks above 90%' unless @lock_critical_notified
    elsif l > 70
      notify '[WARNING] Locks above 70%' unless @lock_warning_notified
    elsif l < 50
      if @lock_warning_notified || @lock_critical_notified
        notify '[Resolved] locks below 50%'
        @lock_warning_notified = false
        @lock_critical_notified = false
      end

    end
  end

  def self.check_and_notify_response_time(avt, requests)
    return unless requests > 200
    if avt > 10_000 || @total_router_errors > 100
      notify "[SEVERE WARNING] Application not healthy | [#{@total_lines} rpm,#{avt} art]" unless @art_critical_notified
      # @art_critical_notified = true
    elsif avt > 500 || @total_router_errors > 10
      notify "[WARNING] Application heating up | [#{@total_lines} rpm,#{avt} art]" unless @art_warning_notified
      # @art_warning_notified = true
    elsif avt < 300
      if @art_warning_notified || @art_critical_notified
        @art_warning_notified = false
        @art_critical_notified = false
      end
    end
  end

  def self.notify(msg)
    Thread.new('notify_admins') do
      subscribers = config[:notify]
      subscribers.each { |user_email| send_email(user_email, msg) } unless subscribers.empty?
    end
  end

  def self.is_number?(string)
    _is_number = true
    begin
      num = Integer(string)
    rescue
      _is_number = false
    end
    _is_number
  end

  def self.send_email(to, msg)
    return unless config[:gmail_username] && config[:gmail_password]
    content = [
        "From: Mongo Watcher <#{config[:gmail_username]}>",
        "To: #{to}",
        "Subject: #{msg}",
        "",
        "RPM: #{@total_lines}",
        "Average Reponse Time: #{average_response_time}",
        "Application Errors: #{@total_web_errors}",
        "Router Errors (timeouts): #{@total_router_errors}",
        "Dynos: #{@dynos}"
    ].join("\r\n")

    Net::SMTP.enable_tls(OpenSSL::SSL::VERIFY_NONE)
    Net::SMTP.start('smtp.gmail.com', 587, 'gmail.com', config[:gmail_username], config[:gmail_password], :login) do |smtp|
      smtp.send_message(content, config[:gmail_username], to)
    end
  end

  def self.color_print(field, options ={})
    options[:length] = 7 unless options[:length]
    print Term::ANSIColor.bold if options[:bold] == true
    if options[:critical] && is_number?(field) && Integer(field) > options[:critical]
      print "\a" #beep
      print Term::ANSIColor.red
      print Term::ANSIColor.bold
    elsif options[:warning] && is_number?(field) && Integer(field) > options[:warning]
      print Term::ANSIColor.yellow
    end
    printf "%#{options[:length]}s", field
    print Term::ANSIColor.clear
  end


end
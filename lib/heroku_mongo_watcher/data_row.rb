require 'term/ansicolor'
require 'heroku_mongo_watcher/configuration'
class HerokuMongoWatcher::DataRow

  # Heroku Attributes
  @@attributes = [:total_requests, :total_service, :total_wait,
                  :total_queue, :total_router_errors, :total_web_errors,
                  :max_service, :slowest_request, :errors, :dynos]

  # Mongo Attributes
  @@attributes.concat [:inserts, :queries, :ops, :updates, :deletes,
                       :faults, :lock, :qrw, :net_in, :net_out]

  @@attributes.each { |attr| attr_accessor attr }

  def initialize
    @@attributes.each { |attr| send "#{attr}=", 0 }
    self.slowest_request = nil
    self.errors = {}
  end

  def config
    HerokuMongoWatcher::Configuration.instance.config
  end

  def average_response_time
    total_requests > 0 ? total_service / total_requests : 'N/A'
  end

  def average_wait
    total_requests > 0 ? total_wait / total_requests : 'N/A'
  end

  def average_queue
    total_requests > 0 ? total_queue / total_requests : 'N/A'
  end

  def process_heroku_router_line(line)
    items = line.split

    if line =~ /Error/
      self.total_router_errors += 1
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
        self.total_requests +=1
        self.total_service += Integer(service) if service
        self.total_wait += Integer(wait) if wait
        self.total_queue += Integer(queue) if queue
        if Integer(service) > self.max_service
          self.max_service = Integer(service)
          self.slowest_request = URI('http://' + url).path
        end
      end

    end
  end

  def process_heroku_web_line(line)
    # Only care about errors
    error_messages = config[:error_messages]

    if error_messages.any? { |mes| line.include? mes }
      items = line.split
      time = items[0]
      process = items[1]
      clean_line = line.sub(time, '').sub(process, '').strip

      self.total_web_errors += 1
      if self.errors.has_key? clean_line
        self.errors[clean_line] = self.errors[clean_line] + 1
      else
        self.errors[clean_line] = 1
      end
    end

  end

  def process_mongo_line(line)
    items = line.split

    @inserts = items[0]
    @queries = items[1]
    @updates = items[2]
    delete = items[3]
    getmore = items[4]
    command = items[5]
    flushes = items[6]
    mapped = items[7]
    vsize = items[8]
    res = items[9]
    @faults = items[10]
    @locked = items[11]
    idx_miss = items[12]
    @qrw = items[13]
    arw = items[14]
    @net_in = items[15]
    @net_out = items[16]
    conn = items[17]
    set = items[18]
    repl = items[19]
    @mongo_time = items[20]

  end

  def self.print_header
    puts
    puts "|<---- heroku stats ------------------------------------------------------------>|<----mongo stats ------------------------------------------------------->|"
    puts "dyno reqs       art    max    r_err w_err   wait  queue slowest                  | insert  query  update  faults locked qr|qw  netIn  netOut    time       |"
  end

  def print_row
    print_errors

    color_print @dynos, length: 4
    color_print @total_requests
    color_print average_response_time, warning: 1000, critical: 10_000, bold: true
    color_print @max_service, warning: 10_000, critical: 20_000
    color_print @total_router_errors, warning: 1, critical: 10
    color_print @total_web_errors, warning: 1, critical: 10
    color_print average_wait, warning: 10, critical: 100
    color_print average_queue, warning: 10, critical: 100
    color_print @slowest_request, length: 28, slice: 25
    print '|'
    color_print @inserts
    color_print @queries
    color_print @updates
    color_print @faults
    color_print @locked, bold: true, warning: 70, critical: 90
    color_print @qrw
    color_print @net_in
    color_print @net_out
    color_print @mongo_time, length: 10
    printf "\n"
  end

  def print_errors
    if config[:print_errors] && @errors && @errors.keys && @errors.keys.length > 0
      @errors.each do |error,count|
        puts "\t\t[#{count}] #{error}"
      end
    end
  end

  private

  def is_number?(string)
    _is_number = true
    begin
      num = Integer(string)
    rescue
      _is_number = false
    end
    _is_number
  end

  def color_print(field, options ={})
    options[:length] = 7 unless options[:length]
    print Term::ANSIColor.bold if options[:bold] == true
    if options[:critical] && is_number?(field) && Integer(field) > options[:critical]
      print "\a" #beep
      print Term::ANSIColor.red
      print Term::ANSIColor.bold
    elsif options[:warning] && is_number?(field) && Integer(field) > options[:warning]
      print Term::ANSIColor.yellow
    end

    str = field.to_s
    str = str.slice(0, options[:slice]) if options[:slice] && str && str.length > 0

    printf "%#{options[:length]}s", str
    print Term::ANSIColor.clear
  end


end
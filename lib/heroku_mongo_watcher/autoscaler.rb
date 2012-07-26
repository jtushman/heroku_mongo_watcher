require 'heroku_mongo_watcher'
require 'heroku_mongo_watcher/data_row'
require 'heroku_mongo_watcher/configuration'
require 'heroku'
class HerokuMongoWatcher::Autoscaler
  include Singleton

  attr_reader :last_scaled, :options

  def initialize(options={})
    @last_scaled = Time.now - 60
    @options = default_options.merge(options)
  end

  def default_options
    {
        min_dynos: 6,
        max_dynos: 50,
        requests_per_dyno: 1000,
        min_frequency: 60 # seconds
    }
  end

  def config
    HerokuMongoWatcher::Configuration.instance.config
  end

  def scale(data_row)

    return if (Time.now - last_scaled) < options[:min_frequency]

    rpm = data_row.total_requests
    current_dynos = data_row.dynos

    ideal_dynos = (rpm / options[:requests_per_dyno]).round

    ideal_dynos = options[:min_dynos] if ideal_dynos < options[:min_dynos]
    ideal_dynos = options[:max_dynos] if ideal_dynos > options[:max_dynos]

    set_dynos(ideal_dynos) if ideal_dynos != current_dynos

  end

  def heroku
    @heroku ||= Heroku::Client.new(config[:heroku_username], config[:heroku_password])
  end

  def set_dynos(count)
    @last_scaled = Time.now
    t = Thread.new('Setting Dynos') do
      puts "! Scaling -> #{count}"
      i = heroku.ps_scale(config[:heroku_appname], :type => 'web', :qty => count)
    end
    t.join

  end


end
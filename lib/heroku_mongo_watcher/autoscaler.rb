require 'heroku_mongo_watcher'
require 'heroku_mongo_watcher/data_row'
require 'heroku_mongo_watcher/configuration'
require 'heroku'
class HerokuMongoWatcher::Autoscaler
  include Singleton

  attr_reader :last_scaled, :options

  def initialize()
    @last_scaled = Time.now - 60
    @options = default_options.merge(config)
  end

  def default_options
    {
        min_dynos: 6,
        max_dynos: 50,
        step: 5,
        requests_per_dyno: 1000,
        min_frequency: 60 # seconds
    }
  end

  def config
    HerokuMongoWatcher::Configuration.instance.config
  end

  # should play it safe and add config[:step] to the calculated result
  # if rpm > 10,000 scale to 15
  # if rpm > 15,000 scale to 20
  # if rpm > 20,000 scale to 25
  # if rpm then drops to 14,000 drop to 15
  # if rpm then drops to 300 drop to 6 (minimum)
  #
  # also do not scale down for 5 minutes
  # always allow to scale up
  def scale(data_row)

    rpm = data_row.total_requests
    current_dynos = data_row.dynos

    # 32,012 rpm => 32 dynos
    ideal_dynos = (rpm / options[:requests_per_dyno]).round

    # return if the delta is less than 5 dynos | don't think I need to do this ...
    #return if (ideal_dynos - current_dynos).abs < options[:step]

    #this turns 32 into 30
    stepped_dynos = (ideal_dynos/options[:step]).round * options[:step]

    #this turns 30 into 35
    stepped_dynos += options[:step]

    #this makes sure that it stays within the min max bounds
    stepped_dynos = options[:min_dynos] if stepped_dynos < options[:min_dynos]
    stepped_dynos = options[:max_dynos] if stepped_dynos > options[:max_dynos]

    # Don't allow downscaling until 5 minutes
    if stepped_dynos < current_dynos && (Time.now - last_scaled) < (60 * 60) # 1 hour
      #puts ">> Current: [#{current_dynos}], Ideal: [#{stepped_dynos}] | will not downscale within an hour"
      nil
    elsif stepped_dynos != current_dynos
      set_dynos(stepped_dynos)
      stepped_dynos
    else
      nil
    end

  end

  def heroku
    @heroku ||= Heroku::Client.new(config[:heroku_username], config[:heroku_password])
  end

  def set_dynos(count)
    @last_scaled = Time.now
    t = Thread.new('Setting Dynos') do
      i = heroku.ps_scale(config[:heroku_appname], :type => 'web', :qty => count)
    end
    t.join

  end


end
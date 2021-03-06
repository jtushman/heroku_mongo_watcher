require 'singleton'
require 'trollop'
require 'heroku_mongo_watcher'

class HerokuMongoWatcher::Configuration
  include Singleton

  @@config = {
      error_messages: ['Error', 'Exception', 'Cannot find impression', 'Timed out running'],
      notify: [],
      gmail_username: '',
      gmail_password: '',
      interval: 60,
      mongo_host: '',
      mongo_username: '',
      mongo_password: '',
      heroku_username: '',
      heroku_password: '',
      heroku_appname: '',
      print_errors: false,
      print_requests: false
  }

  @@valid_config_keys = @@config.keys

  def initialize
    f = File.join(File.expand_path('~'),'.watcher')
    configure_with(f)

    opts = Trollop::options do
      opt :print_errors, "show aggregate error summaries", default: false
      opt :print_requests, "show aggregate requests summaries", default: false
      opt :interval, "frequency in seconds to poll mongostat and print out results", default: 60
      opt :autoscale, "autoscale dynos -- WARNING ONLY DO THIS IF YOU KNOW WHAT YOUR ARE DOING", default: false
      opt :min_dynos, "For autoscaling, the minimum dynos to use", default: 6
      opt :max_dynos, "For autoscaling, the max dynos to use", default: 50
    end

    @@config.merge!(opts)

  end

  def config
    @@config
  end

# Configure through yaml file
  def configure_with(path_to_yaml_file)
    begin
      y_config = YAML::load(IO.read(path_to_yaml_file))
    rescue Errno::ENOENT
      log(:warning, "YAML configuration file couldn't be found. Using defaults."); return
    rescue Psych::SyntaxError
      log(:warning, "YAML configuration file contains invalid syntax. Using defaults."); return
    end

    configure(y_config)
  end

# Configure through hash
  def configure(opts = {})
    opts.each { |k, v| config[k.to_sym] = v if @@valid_config_keys.include? k.to_sym }
  end
end

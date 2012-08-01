require 'eventmachine'
require 'heroku_mongo_watcher'
require 'heroku_mongo_watcher/configuration'

module MongoStatProcessor
  def post_init
    puts "started to read mongostat"
  end

  def receive_data data
    puts "ruby sent me: #{data}"
  end

  def unbind
    puts "ruby died with exit status: #{get_status.exitstatus}"
  end
end


class HerokuMongoWatcher::Watcher

  def self.config
    HerokuMongoWatcher::Configuration.instance.config
  end

  def self.watch

    EM::run {


      cmd = "mongostat --rowcount 0 10 --host #{config[:mongo_host]} \
             --username #{config[:mongo_username]} --password #{config[:mongo_password]} --noheaders"

      EM.popen(cmd, MongoStatProcessor)


    }


  end


end
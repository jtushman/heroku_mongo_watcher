require 'heroku_mongo_watcher'
require 'heroku_mongo_watcher/configuration'

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

class HerokuMongoWatcher::Mailer
  include Singleton
  
  def config
    HerokuMongoWatcher::Configuration.instance.config
  end
  
  def notify(data_row,msg)
    Thread.new('notify_admins') do
      subscribers = config[:notify] || []
      subscribers.each { |user_email| send_email(user_email, msg, data_row) }
    end
  end
  
  protected
  
  def send_email(to, msg, data_row)
    return unless config[:gmail_username] && config[:gmail_password]
    content = [
        "From: Mongo Watcher <#{config[:gmail_username]}>",
        "To: #{to}",
        "Subject: #{msg}",
        "",
        "RPM: #{data_row.total_requests}",
        "Average Reponse Time: #{data_row.average_response_time}",
        "Application Errors: #{data_row.total_web_errors}",
        "Router Errors (timeouts): #{data_row.total_router_errors}",
        "Error Rate: #{data_row.error_rate}%",
        "Dynos: #{data_row.dynos}",
        "",
        "Locks: #{data_row.locked}",
        "Queries: #{data_row.queries}",
        "Inserts: #{data_row.inserts}",
        "Updates: #{data_row.updates}",
        "Faults: #{data_row.faults}",
        "NetI/O: #{data_row.net_in}/#{data_row.net_out}",
    ]
    content = content + data_row.error_content_for_email + data_row.request_content_for_email

    content = content.join("\r\n")
    Net::SMTP.enable_tls(OpenSSL::SSL::VERIFY_NONE)
    Net::SMTP.start('smtp.gmail.com', 587, 'gmail.com', config[:gmail_username], config[:gmail_password], :login) do |smtp|
      smtp.send_message(content, config[:gmail_username], to)
    end
  end
  
end
# Heroku Mongo Watcher

Command line utility to monitor both your mongo and heroku instances, and to alert you when things are heating up

## The Origin

I have a pretty 'spiky' application that can go from having 10_000 requests per minute to 100_000, we need to notified
when things are heating up so we can turn the appropriate dials.  We found new relic to be too slow
(and not accurate enough once throughput levels got high), so we built this.

It needed to accomplish the following:

* See Mongostats and heroku stats at the same time, the key ones being requests per minute, average response time
  lock %, and error counts
* Have multiple ways of notifying stake holders: colors, beeps and email notifications
* Be able to parse the web log for certain errors and other logged events and aggregate data on them

The output looks like the following ...

    |<---- heroku stats ------------------------------------------------------------>|<----mongo stats ------------------------------------------------------->|
    dyno reqs       art    max    r_err w_err   wait  queue slowest                  | insert  query  update  faults locked qr|qw  netIn  netOut    time       |
      20     76     27    586      0      0      0      0   /pxl/4fdbc97dc6b36c003000|      0      0      0      0      0    0|0   305b   257b  15:03:19
      20   1592     62   1292      0      0      0      0   /assets/companions/5009ab|     17      2     32      0    1.2    0|0    14k    26k  15:04:19
    		[4] VAST Error
    		[28] Timeout::Error
    		[11] Cannot find impression when looking for asset
      20  23935    190   7144      0     43      0      0            /crossdomain.xml|    307      0    618      1   21.6    0|0   260k   221k  15:05:19

### Legend
| Term  | Definition |
| dynos | Number of running web instances |
| reqs  | number of requests per sample   |
| art   | average request time |
| max   | max request time |
| r_err | number of router errors, i.e. timeouts |
| w_err | number of web errros (see below) |
| wait  | average router wait |
| queue | average router queue |
| slowest | path of the url that corresponds to the max request time |
| insert | number of mongo inserts |
| query | number of mongo queries |
| update | number of mongo updates |
| faults | number of mongo page faults |
| qr qw | number of mongo's queued read and writes |
| netIn | size on mongo net In |
| netIn | size on mongo net out |
| time | the time sampled |

### Web Errors (w_err)
At least for me, one of the key features is aggregating signals from my web log (I look out for certain race conditions,
and other errors).  You can can configure the `error_messages` array in your .watcher file to define which String we
should report on.

In concert with that is the `display_errors` configuration.  If set to true it will aggregate and display the errors
found (see output above), set to false it will just put the total in the summary row


## Prereqs

1. need to have a heroku account, and have the heroku gem running on your machine
2. need to be able to run mongostat (e.q. has at least read-only admin access to your mongos)

## To install

1. bundle install heroku_mongo_watcher
2. create a .watcher file (see the examples) in your user directory ~/.watcher
3. then run `bundle exec watcher`
4. Ctrl-C out to quit

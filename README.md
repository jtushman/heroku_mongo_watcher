# Heroku Mongo Watcher

I needed to find a way to marry mongo stats with my application stats

It needed to accomplish the following:

* See Mongostats and heroku stats at the same time, the key ones being requests per minute, average response time and lock %
* Have multiple ways of notifying me: colors, beeps and email notifications
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

## Prereqs

1. need to have a heroku account, and have the heroku gem running on your machine

## To install

1. bundle install heroku_mongo_watcher
2. create a .watcher file (see the examples) in your user directory ~/.watcher
3. then run `bundle exec watcher`

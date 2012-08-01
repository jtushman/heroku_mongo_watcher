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

    |<---- heroku stats ------------------------------------------------------------------->|<----mongo stats ------------------------------------------------>|
    | dyno reqs    art   max    r_err  w_err  %err   wait  queue   slowest                  |insrt query updt  flt  lck  lck:mrq qr|qw   netI/O      time      |
       6   3096     57    870      0      2  0.06%      0      0   /assets/companions/50104c|   41     0   79    0 2.2%   0.71    0|0   36k/30k      15:59:29
       6   2705     80   3314      0      0   0.0%      0      0   /assets/companions/50104b|   34     0   67    0   2%   0.74    0|0   30k/25k      16:00:29
       6   2469    122   5708      0      0   0.0%      0      0   /ads/gw/50074348451823003|   30     0   57    0 1.7%   0.69    0|0   26k/22k      16:01:29
       6   2465     89   1347      0      0   0.0%      0      0   /assets/videos/501050b991|   30     0   59    0 1.8%   0.73    0|0   27k/22k      16:02:29
       6   2301     83   1912      0      4  0.17%      0      0   /assets/companions/501050|   28     0   57    0 1.7%   0.74    0|0   25k/21k      16:03:29
       6   1951     64    830      0      0   0.0%      0      0   /ads/gw/50074348451823003|   24     0   45    0 1.4%   0.72    0|0   21k/18k      16:04:29

### Legend
<table>
    <tr><td>dynos</td><td>Number of running web instances</td></tr>
    <tr><td>reqs</td><td>number of requests per sample</td></tr>
    <tr><td>art</td><td>average request time</td></tr>
    <tr><td>max</td><td>max request time</td></tr>
    <tr><td>r_err</td><td>number of router errors, i.e. timeouts</td></tr>
    <tr><td>w_err</td><td>number of web errros (see below)</td></tr>
    <tr><td>%err</td><td>total errors divided by total requests</td></tr>
    <tr><td>wait</td><td>average router wait</td></tr>
    <tr><td>queue</td><td>average router queue</td></tr>
    <tr><td>slowest</td><td>path of the url that corresponds to the max request time</td></tr>
    <tr><td>insert</td><td>number of mongo inserts</td></tr>
    <tr><td>query</td><td>number of mongo queries</td></tr>
    <tr><td>update</td><td>number of mongo updates</td></tr>
    <tr><td>faults</td><td>number of mongo page faults</td></tr>
    <tr><td>lck</td><td>mongo lock percentage</td></tr>
    <tr><td>lck:mrq</td><td>ratio of lock% to 1000 requests</td></tr>
    <tr><td>qr|qw</td><td>number of mongo's queued read and writes</td></tr>
    <tr><td>netIO</td><td>size on mongo net in/ net out</td></tr>
    <tr><td>time</td><td>the time sampled</td></tr>
</table>

### Web Errors (w_err)
At least for me, one of the key features is aggregating signals from my web log (I look out for certain race conditions,
and other errors).  You can can configure the `error_messages` array in your .watcher file to define which String we
should report on.

In concert with that is the `print_errors` configuration.  If set to true it will aggregate and display the errors
found (see output above), set to false it will just put the total in the summary row


## Prereqs

1. need to have a heroku account, and have the heroku gem running on your machine
2. need to be able to run mongostat (e.q. has at least read-only admin access to your mongos), and have mongo installed
locally

## To install

1. gem install heroku_mongo_watcher
2. create a .watcher file (see the examples) in your user directory ~/.watcher
3. then run `bundle exec watcher`
4. Ctrl-C out to quit

## Options

*  `--print-errors` to print a summary of errors during each sample
*  `--print-requests` to print a summary of requests during each sample

note: you can set these defaults in your .watcher file

## Contact

jtushman@pipewave.com

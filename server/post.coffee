child = require 'child_process'
fs = require 'fs'
report = require "#{__dirname}/../client/report.js"
print = (arg...) -> console.log arg...



# 0 * * * * Port=:3000 /usr/local/bin/node /usr/local/lib/node_modules/wiki/node_modules/wiki-plugin-report/server/post.js
# Site=localhost Port=:3000 Debug=true Data=/Users/ward/.wiki /usr/local/bin/node post.js

Site = process.env.Site or null
Port = process.env.Port or ''
Farm = process.env.Farm or '.wiki' unless Site
Data = process.env.Data or '.wiki' if Site
Sufix = process.env.Sufix or 'report'
Debug = process.env.Debug is 'true'



# Fetch data from wiki farm files

findPaths = (done) ->
  if Farm
    child.exec "/bin/ls #{Farm}/*/pages/*-#{Sufix}", (err, stdout, stderr) ->
      return print 'findPaths (Farm)', err if err
      for path in stdout.split /\n/
        continue if path is ''
        [slug,x,site] = path.split('/').reverse()
        done path, site, slug
  else
    child.exec "/bin/ls #{Data}/pages/*-#{Sufix}", (err, stdout, stderr) ->
      return print 'findPaths (Site)', err if err
      for path in stdout.split /\n/
        continue if path is ''
        [slug] = path.split('/').reverse()
        done path, Site, slug

fetchPage = (path, done) ->
  text = fs.readFile path, 'utf8', (err, text) ->
    return print 'fetchPage', path, err if err
    done JSON.parse text

findSchedule = (page) ->
  for item in page.story
    return report.parse(item.text) if item.type is 'report'
  null

findPubs = (done) ->
  findPaths (path, site, slug) ->
    fetchPage path, (page) ->
      if schedule = findSchedule page
        for issue in schedule
          if issue.interval? and issue.recipients?.length
            done {site, slug, page, schedule, issue}



# Compose summary from story and journal

links = (text) ->
  text.replace /\[(http.*?) +(.*?)\]/gi, "[$2]"

flow = (text) ->
  text.replace(/\s+/g, ' ') + "\n"

fold = (text) ->
  # http://james.padolsey.com/javascript/wordwrap-for-javascript/
  text.match(/.{1,50}(\s|$)|\S+?(\s|$)/g).join "\n"

compose = (page, since) ->
  active = {}
  for action in page.journal
    if action.date and action.date > since
      active[action.id] = 'NEW' if action.type == 'add'
      active[action.id] = 'UPDATE' if action.type == 'edit' and not active[action.id]
  result = []
  for item in page.story
    if item.type is 'paragraph' and active[item.id]
      result.push active[item.id]
      result.push fold flow links item.text
  result.join "\n"

ready = ({issue, now, period}) ->
  window = period*60*1000
  thisIssue = report.advance(now, issue, 0)
  lapse = now.getTime() - thisIssue.getTime()
  lapse < window



# Hand off to sendmail for distribution

header = (fields) ->
  ("#{k}: #{v}" for k, v of fields).join "\n"

enclose = ({site, slug, page, issue, summary}) ->
  [header
    To: issue.recipients.join ", "
    'Reply-to': issue.recipients.join ", "
    Subject: "#{page.title} (#{issue.interval})"
  "#{page.title}\nPublished #{issue.interval} from Federated Wiki"
  summary
  "See details at\nhttp://#{site}#{Port}/#{slug}.html"].join "\n\n"

sendmail = (pub) ->
  output = []
  send = child.spawn '/usr/sbin/sendmail', ['-fward@wiki.org', '-t']
  send.stdin.write pub.message
  send.stdin.end()
  send.stderr.setEncoding 'utf8'
  send.stderr.on 'data', (data) -> output.push data
  send.on 'exit', (code) ->
    print "sent #{pub.page.title} (#{pub.issue.interval}), code: #{code}" if Debug
    print output.join '' if output.length



# Main program loops over all publications

findPubs (pub) ->
  pub.now = new Date(2012,12-1,21,0,0,3)
  pub.now = new Date()
  pub.period = 30
  print pub.site, pub.slug if Debug
  if ready pub
    pub.summary = compose pub.page, report.advance(pub.now, pub.issue, -1)
    if pub.summary is ''
      print "nothing to send" if Debug
    else
      pub.message = enclose pub
      sendmail pub
  else
    print report.explain pub.issue if Debug


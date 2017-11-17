# Description:
#   GitHubの最近のコミット履歴を調べ、煽ります。
#

cron = require('cron').CronJob

moment = require('moment-timezone')
moment.tz.setDefault("Asia/Tokyo")

GITHUB_USERS =
  "tkrplus":"@Niwa.Takeru"
  "wtrmgmg":"@Mogi.Wataru"
  "r-manase":"@Masutani.Yuichi"

GITHUB_USERNAME = "mmncloud"
GITHUB_BASE_URL = "https://api.github.com"
TARGET_ROOM = room: "sandbox"
AORI_MONKU = ["今日は草生やしてないっすけど良いんすか？ｗｗｗｗ",
  "今日は更地ですけど、もしかして芝刈り機にやられちゃいました？？ｗ",
  "となりの芝はあおいっすね〜ｗｗｗｗ",　
  "たまには草生やしてくださいよ〜ぱいせ〜んｗｗｗ",
  "不毛地帯できちゃってますよ〜？？ｗｗｗｗ",
  "草も生えてないとかｗｗｗ大草原不可避ｗｗｗｗｗｗ",
  "今日は生えてないな。お前の頭のように。",
  "草生えないのが許されるのは小学生までだよね〜ｗｗｗｗ",
  "えっ...あなたのContribution Log, もしかして禿げすぎ？"]
AORI_REF_TIME = hour: 4

GITHUB_PROJECTS = ["mmn-bot", "react-sandbox"]

module.exports = (robot) ->

  new cron('0 0 22 * * *', () ->
    referenceDate = getAoriReferenceDate(moment())

    for user, value of GITHUB_USERS
      checkUserCommits(user, referenceDate.dateFrom, referenceDate.dateTo)
  ).start()

  robot.respond /github checkCommits (.*)/i, (msg) ->
    user = msg.match[1]
    referenceDate = getAoriReferenceDate(moment())
    checkUserCommits(user, referenceDate.dateFrom, referenceDate.dateTo)

  new cron('0 0 20 * * *', () ->
    room = getRoomByName "sandbox"
    robot.send {room:room}, "20時でーす。プルリク確認しまーす。"
    checkPullRequests room
  ).start()

  robot.hear /^@ぷるりく|@プルリク$/i, (msg) ->
    checkPullRequests msg.envelope.room

  robot.hear /^@ぷるりく|@プルリク (.*)/i, (msg) ->
    checkRepositoryPullRequests msg.envelope.room, GITHUB_USERNAME, msg.match[1]

  # 指定された期間内にコミットイベント（プッシュイベントがない場合は煽る）
  checkUserCommits = (user, dateFrom, dateTo) ->
    request = robot.http(getGitHubApiURL "/users/#{user}/events")
      .get()
    request (err, response, body) ->
      if err
        robot.logger.debug err
        return
      data = JSON.parse body
      commitCount = 0
      for event in data
        unless event.type == "PushEvent"
          continue
        createAt = moment(event.created_at)
        unless existsBetweenRefDateRange(createAt, dateFrom, dateTo)
          continue
        commitCount++
      if commitCount > 0
        return
      message = AORI_MONKU[random(AORI_MONKU.length)]
      robot.logger.debug user
      robot.logger.debug GITHUB_USERS
      robot.logger.debug GITHUB_USERS[user]
      message = "#{getSlackUserByGitHubUser(user)}\n#{message}"
      robot.send TARGET_ROOM, message

  existsBetweenRefDateRange =(createAt, referenceDateFrom, referenceDateTo) ->
    return referenceDateFrom.isBefore(createAt) and referenceDateTo.isAfter(createAt)

  getAoriReferenceDate = (checkingDate, configuredReferenceTime = AORI_REF_TIME) ->
    if checkingDate.isAfter(moment(configuredReferenceTime))
      return referenceDate =
        dateFrom : moment(configuredReferenceTime)
        dateTo : moment(configuredReferenceTime).add(1, 'days')
    else
      return referenceDate =
        dateFrom : moment(configuredReferenceTime).subtract(1, 'days')
        dateTo : moment(configuredReferenceTime)

  random = (n) -> Math.floor(Math.random() * n)

  getSlackUserByGitHubUser = (gitHubUser) ->
    return GITHUB_USERS[gitHubUser]

  getRoomByName = (name) ->
    channel = robot.adapter.client.rtm.dataStore.getChannelOrGroupByName name
    return channel.id

  checkPullRequests = (room) ->
    request = robot.http(getGitHubApiURL "/users/#{GITHUB_USERNAME}/repos").get()
    request (err, response, body) ->
      if err
        robot.logger.debug err
        return
      data = JSON.parse body
      for value, index in data
        checkRepositoryPullRequests room, value.owner.login, value.name

  checkRepositoryPullRequests = (room, owner, repository) ->
    request = robot.http(getGitHubApiURL "/repos/#{owner}/#{repository}/pulls", {sort:"updated"}).get()
    request (err, response, body) ->
      if err
        robot.logger.debug err
        return
      data = JSON.parse body
      for pullRequest, index in data
        reviewee = getSlackUserByGitHubUser(pullRequest.user.login)
        reviewerList = []
        for reviewer, i in pullRequest.requested_reviewers
          name = getSlackUserByGitHubUser(reviewer.login)
          unless name
            return
          reviewerList.push name
        reviewerUsers = reviewerList.join ' '
        daysAgo = moment().diff(moment(pullRequest.created_at), 'days')
        overview = pullRequest.body.split('\r\n')[1]
        slackCustomMessage =
          color: "#19B5FE"
          title: "【#{pullRequest.head.repo.name}】#{pullRequest.title}"
          title_link: pullRequest.html_url
          fields:[
              title: "Reviewee"
              value: reviewee
              short: true
            ,
              title: "Reviewer"
              value: reviewerUsers
              short: true
            , 
              title: "Overview"
              value: "#{overview} #{daysAgo}日前"
              short: false
          ]
          thumb_url: pullRequest.user.avatar_url
          mrkdwn_in: ['text']
        robot.send {room: room}, {attachments: [slackCustomMessage]}

  getGitHubApiURL = (path) ->
    return getGitHubApiURL path, {}

  getGitHubApiURL = (path, paramMap) ->
    accessToken = if process.env.GITHUB_TOKEN then { access_token: process.env.GITHUB_TOKEN } else {}
    param = Object.assign accessToken, paramMap
    paramList = []
    for key, value of param
      paramList.push "#{encodeURIComponent(key)}=#{encodeURIComponent(value)}"
    paramString = paramList.join '&'
    return "#{GITHUB_BASE_URL}#{path}?#{paramString}"
    
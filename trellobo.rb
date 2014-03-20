require 'cinch'
require 'trello'
require 'json'
require 'resolv'
require 'mongo'

# You will need an access token to use ruby-trello 0.3.0 or higher, which trellobo depends on. To
# get it, you'll need to go to this URL:
#
# https://trello.com/1/connect?key=DEVELOPER_PUBLIC_KEY&name=trellobo&response_type=token&scope=read,write&expiration=never
#
# Substitute the DEVELOPER_PUBLIC_KEY with the value you'll supply in TRELLO_API_KEY below. At the end of this process,
# You'll be told to give some key to the app, this is what you want to put in the TRELLO_API_ACCESS_TOKEN_KEY below.
#
# there are several environment variables that must (could in some cases) be set for the trellobot to behave
# the way he is supposed to -
#
# TRELLO_API_KEY : your Trello API developer key
# TRELLO_API_SECRET : your Trello API developer secret
# TRELLO_API_ACCESS_TOKEN_KEY : your Trello API access token key. See above how to generate it.
# TRELLO_BOARD_ID : the trellobot looks at only one board and the lists on it, put its id here
# TRELLO_HELP_BOARD_ID : the id of the trello board for help requests
# TRELLO_BOT_QUIT_CODE : passcode to cause trellobot to quit - defaults to none
# TRELLO_BOT_CHANNEL : the name of the channel you want trellobot to live on
# TRELLO_BOT_CHANNEL_KEY : the password of the channel you want trellobot to live on. Optional
# TRELLO_BOT_NAME : the name for the bot, defaults to 'trellobot'
# TRELLO_BOT_SERVER : the server to connect to, defaults to 'irc.freenode.net'
# TRELLO_BOT_SERVER_USE_SSL : if ssl is required set this variable to "true" if not, do not set it at all. Optional
# TRELLO_BOT_SERVER_SSL_PORT : if ssl is used set this variable to the port number that should be used. Optional
# TRELLO_ADD_CARDS_LIST : all cards are added at creation time to a default list. Set this variable to the name of this list, otherwise it will default to To Do. Optional
# TRELLO_ADD_HELP_CARDS_LIST : the id of the trello list for help requests
# TRELLO_HELP_CLAIMED_LIST : the id of the trello list for claimed help requests

$board = nil
$add_cards_list = nil
$add_help_cards_list = nil
$login_collection = 'logins'

include Trello
include Trello::Authorization
include Mongo

Trello::Authorization.const_set :AuthPolicy, OAuthPolicy
OAuthPolicy.consumer_credential = OAuthCredential.new ENV['TRELLO_API_KEY'], ENV['TRELLO_API_SECRET']
OAuthPolicy.token = OAuthCredential.new ENV['TRELLO_API_ACCESS_TOKEN_KEY'], nil

def given_short_id_return_long_id(board, short_id)
  long_ids = board.cards.collect { |c| c.id if c.url.match(/\/(\d+).*$/)[1] == short_id.to_s}
  long_ids.delete_if {|e| e.nil?}
end

def get_list_by_name(name)
  $board.lists.find_all {|l| l.name.casecmp(name.to_s) == 0}
end

def sync_board
  return $board.refresh! if $board
  $board = Trello::Board.find(ENV['TRELLO_BOARD_ID'])
  $help_board = Trello::Board.find(ENV['TRELLO_HELP_BOARD_ID'])
  $add_cards_list = $board.lists.detect { |l| l.name.casecmp(ENV['TRELLO_ADD_CARDS_LIST']) == 0 }
  $add_help_cards_list = $help_board.lists.detect { |l| l.name.casecmp(ENV['TRELLO_ADD_HELP_CARDS_LIST']) == 0 }
  $help_claimed_board = $help_board.lists.detect { |l| l.name.casecmp(ENV['TRELLO_HELP_CLAIMED_LIST']) == 0 }
end

def db_connect
  db = MongoClient.new('localhost', 27018).db('trellobo')
  db.authenticate(ENV['OPENSHIFT_MONGODB_DB_USERNAME'], ENV['OPENSHIFT_MONGODB_DB_PASSWORD'])
  return db
end

def store_login(nick, login)
  db = db_connect
  db[$login_collection].insert({'nick' => nick, 'login' => login})
end

def get_login(nick)
  db = db_connect
  db[$login_collection].find_one({'nick' => nick})['login']
end

def say_help(msg)
  msg.reply "I can tell you the open cards on the lists on your Trello board. Just address me with the name of the list (it's not case sensitive)."
  msg.reply "For example - trellobot: ideas"
  msg.reply "I also understand the these commands : "
  msg.reply "  ->  1. help - shows this!"
  msg.reply "  ->  2. sync - resyncs my cache with the board."
  msg.reply "  ->  3. lists - show me all the board list names"
  msg.reply "  ->  4. card add this is a card - creates a new card named: \'this is a card\' in a list defined in the TRELLO_ADD_CARDS_LIST env variable or if it\'s not present in a list named To Do"
  msg.reply "  ->  5. card <id> comment this is a comment on card <id> - creates a comment on the card with short id equal to <id>"
  msg.reply "  ->  6. card <id> move to Doing - moves the card with short id equal to <id> to the list Doing"
  msg.reply "  ->  7. card <id> add member joe - assign joe to the card with short id equal to <id>."
  msg.reply "  ->  8. cards joe - return all cards assigned to joe"
  msg.reply "  ->  9. card <id> link - return a link to the card with short id equal to <id>"
  msg.reply "  -> 10. help me TASK1337 - creates a new card named: \'help with TASK1337\' on the help board"
  msg.reply "  -> 11. help requests - show unclaimed help requests"
  msg.reply "  -> 12. help with <id> - add yourself as a member on a help request card with id equal to <id>"
end

bot = Cinch::Bot.new do
  configure do |c|
    # Initialize defaults for optional envs
    ENV['TRELLO_BOT_QUIT_CODE'] ||= ""
    ENV['TRELLO_BOT_NAME'] ||= "trellobot"
    ENV['TRELLO_BOT_SERVER'] ||= "irc.freenode.net"
    ENV['TRELLO_ADD_CARDS_LIST'] ||= "To Do"
    ENV['TRELLO_ADD_HELP_CARDS_LIST']

    c.server = ENV['TRELLO_BOT_SERVER']
    c.nick = ENV['TRELLO_BOT_NAME']

    if !ENV["TRELLO_BOT_CHANNEL_KEY"].nil? and ENV["TRELLO_BOT_CHANNEL_KEY"] != ""
      c.channels = ["#{ENV['TRELLO_BOT_CHANNEL']} #{ENV['TRELLO_BOT_CHANNEL_KEY']}"]
    else
      c.channels = [ENV['TRELLO_BOT_CHANNEL']]
    end
    if ENV['TRELLO_BOT_SERVER_USE_SSL'] == "true"
      c.port = ENV['TRELLO_BOT_SERVER_SSL_PORT'] ||= "6697"
      c.ssl.use = true
    end
    sync_board
  end

  intro = /^#{ENV['TRELLO_BOT_NAME']}_*[:,] (.*)/

  # trellobot is polite, and will only reply when addressed
  on :message, intro do |m|
    # if trellobot can't get thru to the board, then send the human to the human url
    sync_board unless $board and $help_board
    unless $board and $help_board
      m.reply "I can't seem to get the list of ideas from Trello, sorry. Try here: https://trello.com/board/#{ENV['TRELLO_BOARD_ID']} or here: https://trello.com/board/#{ENV['TRELLO_HELP_BOARD_ID']}"
      bot.halt
    end

    # trellobot: what up?  <- The bit we are interested in is past the ':'
    searchfor = intro.match(m.message)[1]
    searchfor = searchfor.strip.downcase

    case searchfor
    when /debug/
      debugger
    when /^card add/
      if $add_cards_list.nil?
        m.reply "Can't add card. It wasn't found any list named: #{ENV['TRELLO_ADD_CARDS_LIST']}."
      else
        m.reply "Creating card ... "
        name = searchfor.strip.match(/^card add (.+)$/)[1]
        card = Trello::Card.create(:name => name, :list_id => $add_cards_list.id)
        m.reply "Created card #{card.name} with id: #{card.short_id}."
      end
    when /^card \d+ comment/
      m.reply "Commenting on card ... "
      card_regex = searchfor.match(/^card (\d+) comment (.+)/)
      card_id = given_short_id_return_long_id($board, card_regex[1])
      if card_id.count == 0
        m.reply "Couldn't be found any card with id: #{card_regex[1]}. Aborting"
      elsif card_id.count > 1
        m.reply "There are #{list.count} cards with id: #{regex[1]}. Don't know what to do. Aborting"
      else
        comment = card_regex[2]
        card = Trello::Card.find(card_id[0].to_s)
        card.add_comment comment
        m.reply "Added \"#{comment}\" comment to \"#{card.name}\" card"
      end
    when /^card \d+ move to .+/
      m.reply "Moving card ... "
      regex = searchfor.match(/^card (\d+) move to (.+)/)
      list = get_list_by_name(regex[2].to_s)
      card_id = given_short_id_return_long_id($board, regex[1].to_s)
      if card_id.count == 0
        m.reply "Couldn't be found any card with id: #{regex[1]}. Aborting"
      elsif card_id.count > 1
        m.reply "There are #{list.count} cards with id: #{regex[1]}. Don't know what to do. Aborting"
      else
        if list.count == 0
          m.reply "Couldn't be found any list named: \"#{regex[2].to_s}\". Aborting"
        elsif list.count > 1
          m.reply "There are #{list.count} lists named: #{regex[2].to_s}. Don't know what to do. Aborting"
        else
          card = Trello::Card.find(card_id[0])
          list = list[0]
          if card.list.name.casecmp(list.name) == 0
            m.reply "Card \"#{card.name}\" is already on list \"#{list.name}\"."
          else
            card.move_to_list list
            m.reply "Moved card \"#{card.name}\" to list \"#{list.name}\"."
          end
        end
      end
    when /^card \d+ add member \w+/
      m.reply "Adding member to card ... "
      regex = searchfor.match(/^card (\d+) add member (\w+)/)
      card_id = given_short_id_return_long_id($board, regex[1].to_s)
      if card_id.count == 0
        m.reply "Couldn't be found any card with id: #{regex[1]}. Aborting"
      elsif card_id.count > 1
        m.reply "There are #{list.count} cards with id: #{regex[1]}. Don't know what to do. Aborting"
      else
        card = Trello::Card.find(card_id[0])
        membs = card.members.collect {|m| m.username}
        begin
          member = Trello::Member.find(regex[2])
        rescue
          member = nil
        end
        if member.nil?
          m.reply "User \"#{regex[2]}\" doesn't exist in Trello."
        elsif membs.include? regex[2]
          m.reply "#{member.full_name} is already assigned to card \"#{card.name}\"."
        else
          card.add_member(member)
          m.reply "Added \"#{member.full_name}\" to card \"#{card.name}\"."
        end
      end
    when /^cards \w+/
      username = searchfor.match(/^cards (\w+)/)[1]
      cards = []
      cid_length = 1
      $board.cards.each do |card|
        members = card.members.collect { |mem| mem.username }
        if members.include? username
          cards << card
          cid_length = card.short_id.to_s.length if card.short_id.to_s.length > cid_length
        end
      end
      if cards.count == 0
        m.reply "User \"#{username}\" has no cards assigned."
      end
      cards.sort! { |c1, c2| c1.short_id.to_i <=> c2.short_id.to_i }
      cards.each do |c|
        m.reply "  ->  #{c.short_id.to_s.rjust(cid_length)}. #{c.name} from list: #{c.list.name}"
      end
    when /^card \d+ link/
      regex = searchfor.match(/^card (\d+) link/)
      card_id = given_short_id_return_long_id($board, regex[1].to_s)
      if card_id.count == 0
        m.reply "Couldn't be found any card with id: #{regex[1]}. Aborting"
      elsif card_id.count > 1
        m.reply "There are #{list.count} cards with id: #{regex[1]}. Don't know what to do. Aborting"
      else
        card = Trello::Card.find(card_id[0])
        msg_err = nil
        m.reply card.url
      end
    when /lists/
      $board.lists.each { |l|
        m.reply "  ->  #{l.name}"
      }
    when /^help$/
      say_help(m)
    when /\?/
      say_help(m)
    when /sync/
      sync_board
      m.reply "Ok, synced the board, #{m.user.nick}."
    when /help me .*/
      if $add_help_cards_list.nil?
        m.reply "Can't add card. It wasn't found any list named: #{ENV['TRELLO_ADD_CARDS_LIST']}."
      else
        m.reply "Requesting help ... "
        regex = searchfor.strip.match(/^help me (.*)/)
        name = regex[1]
        card = Trello::Card.create(:name => name, :list_id => $add_help_cards_list.id)
        m.reply "Created card #{card.name} with id: #{card.short_id}."
      end
    when /help requests/
      cards = []
      if $add_help_cards_list.cards.length == 0
        m.reply "No cards on the #{$add_help_cards_list.name} list."
      end
      cid_length = 1
      $add_help_cards_list.cards.each do |c|
          cid_length = card.short_id.to_s.length if card.short_id.to_s.length > cid_length
      end
      $add_help_cards_list.cards.each do |c|
        m.reply "  ->  #{c.short_id.to_s.rjust(cid_length)}. #{c.name} from list: #{c.list.name}"
      end
    when /help with .*/
      regex = /help with (\d+)/.match(m.message)
      card_id = given_short_id_return_long_id($help_board, regex[1].to_s)
      nick = m.user.nick.split('|')[0]
      user = Trello::Member.find(get_login(nick))
      m.reply "You must register your Trello username first! (eg: /msg #{ENV['TRELLO_BOT_NAME']} register <trello_username>)" unless user
      card = Trello::Card.find(card_id[0])
      m.reply "Helping with #{card.name}..."
      card.add_member(user)
      card.move_to_list($help_claimed_board)
      m.reply "Added you to card #{card.name}."
    else
      if searchfor.length > 0
        # trellobot presumes you know what you are doing and will attempt
        # to retrieve cards using the text you put in the message to him
        # at least the comparison is not case sensitive
        list = $board.lists.detect { |l| l.name.casecmp(searchfor) == 0 }
        if list.nil?
          m.reply "There's no list called <#{searchfor}> on the board, #{m.user.nick}. Sorry."
        else
          cards = list.cards
          if cards.count == 0
            m.reply "Nothing doing on that list today, #{m.user.nick}."
          else
            ess = (cards.count == 1) ? "" : "s"
            m.reply "I have #{cards.count} card#{ess} today in list #{list.name}"
            inx = 1
            cards.each do |c|
              membs = c.members.collect {|m| m.full_name }
              if membs.count == 0
                m.reply "  ->  #{inx.to_s}. #{c.name} (id: #{c.short_id})"
              else
                m.reply "  ->  #{inx.to_s}. #{c.name} (id: #{c.short_id}) (members: #{membs.to_s.gsub!("[","").gsub!("]","").gsub!("\"","")})"; inx += 1
              end
              inx += 1
            end
          end
        end
      else
        say_help(m)
      end
    end
  end

  # if trellobot loses his marbles, it's easy to disconnect him from the server
  # note that if you are doing a PaaS deploy, he may respawn depending on what
  # the particular hosting env is (e.g. Heroku will start him up again)
  on :private do |m|
    case m.message
    when /^quit\s*\w*/ 
      code = /^quit\s*(\w*)/.match(m.message)[1]
      bot.quit if ENV['TRELLO_BOT_QUIT_CODE'].eql?(code)

      if code.empty?
        m.reply "There is a quit code required for this bot, sorry."
      else
        m.reply "That is not the correct quit code required for this bot, sorry."
      end
    when /^register/
      nick = m.user.nick.split('|')[0]
      login = /^register (.*)/.match(m.message)[1]
      m.reply "Registering #{nick} as #{login}"
      store_login(nick, login)
      m.reply "Done!"
    end
  end
end

bot.start

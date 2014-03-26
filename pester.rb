#!/bin/env ruby

require 'cinch'
require_relative './utils.rb'

class Pester
  include Cinch::Plugin

  listen_to :channel, {method: :pester_users}
  listen_to :nick, {method: :pester_users}

  def pester_users(m)
    shortnick = nick_parse(m.user.nick)

    pestered_today = db_connect do |db|
      db[$login_collection].find_one({'_id' => shortnick})['pestered_today']
    end

    return if pestered_today

    if registered_nicks.include?(shortnick)
      lonely_cards(shortnick).each do |card|
        m.user.send("please update #{card['card_url']}")
      end
    end

    db_connect do |db|
      doc = db[$login_collection].find_one({'_id' => shortnick})
      doc['pestered_today'] = true
      db[$login_collection].update({'_id' => shortnick}, doc)
    end
  end
end

require 'sinatra'
require 'dotenv'
require 'json'
require 'net/http'
require 'slim'
require 'sinatra/reloader' if development?
Dotenv.load
$region = 'euw' #this will be a parameter
$api_base_address = "https://#{$region}.api.pvp.net"
API_KEY_SUFFIX = "?api_key=#{ENV['APIKEY']}"

set :environment, :development
helpers do
    def get_champion_name(id)
        result = JSON.parse(Net::HTTP.get(URI.parse(URI.encode("https://global.api.pvp.net/api/lol/static-data/#{$region}/v1.2/champion/#{id}"+ API_KEY_SUFFIX))))['name']
    end
    def get_summoner_info(names)
        info = JSON.parse(Net::HTTP.get(URI.parse(URI.encode("https://#{$region}.api.pvp.net/api/lol/#{$region}/v1.4/summoner/by-name/#{names}" + API_KEY_SUFFIX))))
    end

    def get_summoner_league(summoner_id)
        result = JSON.parse(Net::HTTP.get(URI.parse(URI.encode("https://#{$region}.api.pvp.net/api/lol/#{$region}/v2.5/league/by-summoner/#{summoner_id}/entry" + API_KEY_SUFFIX))))
    end

    def get_summoner_summary(summoner_id)
        result = JSON.parse(Net::HTTP.get(URI.parse(URI.encode("https://#{$region}.api.pvp.net/api/lol/#{$region}/v1.3/stats/by-summoner/#{summoner_id}/summary" + API_KEY_SUFFIX))))
    end

    def get_match_history(summoner_id)
        matchhistory = JSON.parse(Net::HTTP.get(URI.parse(URI.encode("https://#{$region}.api.pvp.net/api/lol/#{$region}/v2.2/matchhistory/#{summoner_id}" + API_KEY_SUFFIX))))
        matches =  matchhistory.values[0]
        clear_match = []
        matches.each do |match|
            clear_match << 
            {
                :champion => get_champion_name(match['participants'][0]['championId']),
                :stats => "#{match['participants'][0]['stats']['kills']}/#{match['participants'][0]['stats']['deaths']}/#{match['participants'][0]['stats']['assists']}",
                :queue => match['queueType'],
                :won =>  match['participants'][0]['stats']['winner']
            }
        end
        clear_match
    end
    def get_stat_summary_for_ranked(summary)
        res = []
        data = summary['playerStatSummaries']
        dupa = data.index{|c| c['playerStatSummaryType']=='RankedSolo5x5'}
        dupa2 = data.index{|c| c['playerStatSummaryType']=='Unranked'}
        res << data[dupa].select {|k,v| ['wins', 'losses'].include?(k)} if dupa
        res << data[dupa2].select{|k,v| ['wins'].include?(k)} if dupa2
    end

    def parse_names_from_params(chatlog, manual)
        names = []
        puts "dupa"
        #TODO: think about recombining into one regexp
        names += chatlog.scan(/([A-Za-z0-9 ]+) joined the room/)
        chatlog.lines.each { |l| names << l.scan(/^([A-Za-z0-9 ]+):/) }
        names += manual.split(",").map(&:chomp)
        return names.flatten.uniq.to_ary
    end

end
get '/' do
    slim :home
end
post '/' do
    puts params
    $region = params['region']
    puts $api_base_address
    redirect '/' unless params['chatlog'] !="" || params['manualEntry'] != ""
    team = parse_names_from_params(params['chatlog'], params['manualEntry'])
    puts '----------'
    puts team
    puts '----------'
    @summoner_info = {}
    id_info = get_summoner_info(team.join(", "))
    puts id_info
    team.each do |tm|
        id = id_info[tm.downcase.gsub(' ', '')]['id']
        @summoner_info[id] = {}
        @summoner_info[id]['name'] = tm
        # @summoner_info[id]['match_history'] = get_match_history(id)
        # puts " getting match history time: #{Time.now - start}"
        @summoner_info[id]['summary'] = get_stat_summary_for_ranked(get_summoner_summary(id))
    end
        # @summoner_info[id]['league_info'] = get_summoner_league(id)# todo:refractor in a way that this returns actual league info for one summoner
    slim :dream_team
end

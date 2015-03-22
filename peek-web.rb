require 'sinatra'
require 'dotenv'
require 'json'
require 'net/http'
require 'slim'
require 'sinatra/flash'
require 'sinatra/reloader' if development?

Dotenv.load
enable :sessions
$api_base_address = "https://#{$region}.api.pvp.net"
API_KEY_SUFFIX = "?api_key=#{ENV['APIKEY']}"
helpers do
    def get_champion_name(id)
        result = JSON.parse(Net::HTTP.get(URI.parse(URI.encode(
            "https://global.api.pvp.net/api/lol/static-data/#{$region}/v1.2/champion/#{id}"+ API_KEY_SUFFIX))))['name']
    end

    def get_summoner_info(names)
        begin
            info = JSON.parse(Net::HTTP.get(URI.parse(URI.encode(
                "https://#{$region}.api.pvp.net/api/lol/#{$region}/v1.4/summoner/by-name/#{names}" + API_KEY_SUFFIX))))
        rescue JSON::ParserError
            info = nil
        end
    end

    def get_summoners_league_info(ids)
        begin
            result =JSON.parse(Net::HTTP.get(URI.parse(URI.encode(
                "https://#{$region}.api.pvp.net/api/lol/#{$region}/v2.5/league/by-summoner/#{ids}/entry" + API_KEY_SUFFIX))))
        rescue JSON::ParserError
            result = nil 
        end
    end

    def get_stat_summary(summoner_id)
        res = {} 
        # todo: refractor this. Feeling shaky about hardcoding the previous season, and it would be good to present data from both (current and previous) anyways
        summary = JSON.parse(Net::HTTP.get(URI.parse(URI.encode(
            "https://#{$region}.api.pvp.net/api/lol/#{$region}/v1.3/stats/by-summoner/#{summoner_id}/summary" + API_KEY_SUFFIX))))
        if !summary.keys.include?('playerStatSummaries')    # i.e. player has not been active this season
            #get the stats from last season: because who's ever going to check a player from 2013 and before?
            summary = JSON.parse(Net::HTTP.get(URI.parse(URI.encode(
                "https://#{$region}.api.pvp.net/api/lol/#{$region}/v1.3/stats/by-summoner/#{summoner_id}/summary?season=SEASON2014&api_key=#{ENV['APIKEY']}")))) 
        end
        data = summary['playerStatSummaries']
        dupa = data.index{|c| c['playerStatSummaryType']=='RankedSolo5x5'}
        dupa2 = data.index{|c| c['playerStatSummaryType']=='Unranked'}
        res['rankedStats'] = data[dupa].select {|k,v| ['wins', 'losses'].include?(k)} if dupa
        res['normalStats'] = data[dupa2].select{|k,v| ['wins'].include?(k)} if dupa2
        res
    end

    def parse_names_from_params(chatlog, manual)
        names = []
        # todo: join in one scan? 
        names += chatlog.scan(/([A-Za-z0-9 ]+) joined the room/)
        chatlog.lines.each { |l| names << l.scan(/^([A-Za-z0-9 ]+):/) }
        names += manual.split(",").map(&:chomp)
        return names.flatten.uniq.to_ary
    end

    def parse_league_info(league_info_for_summoner)
        res = {}
        if league_info_for_summoner
            idx_5x5_solo = league_info_for_summoner.index {|c| c['queue']=="RANKED_SOLO_5x5"}
            idx_5x5_team = league_info_for_summoner.index {|c| c['queue']=="RANKED_TEAM_5x5"}
            res["rankedSoloLeague"] = league_info_for_summoner[idx_5x5_solo].select {|k,v| ['tier', 'entries'].include?(k)} if idx_5x5_solo
            res["rankedTeamLeague"] = league_info_for_summoner[idx_5x5_team].select{|k,v| ['tier', 'entries'].include?(k)} if idx_5x5_team
            res
        end
    end
end

get '/' do
    slim :home
end

post '/results' do
    redirect '/' unless params['chatlog'] !="" || params['manualEntry'] != ""
    $region = params['region']
    team = parse_names_from_params(params['chatlog'], params['manualEntry'])
    id_info = get_summoner_info(team.join(", "))
    if !id_info
        flash[:errors] = "Couldn't find provided summoner name(s). Are you sure you put in the right thing?" # todo: wording?
        redirect '/'
    else
        @summoner_info = {}
        league_info = get_summoners_league_info(id_info.values.map{|i| i['id'] if i['id']}.join(", "))
        team.each do |tm|
            begin
                id = id_info[tm.downcase.gsub(' ', '')]['id']
                puts id
                lg_i = parse_league_info(league_info[id.to_s])
                summary = get_stat_summary(id)
                @summoner_info[id] = {}
                @summoner_info[id]['name'] = tm
                @summoner_info[id]['tier'] = lg_i['rankedSoloLeague'] ? "#{lg_i["rankedSoloLeague"]["tier"].capitalize} #{lg_i["rankedSoloLeague"]["entries"][0]["division"]}" : "Unranked"
                @summoner_info[id]['rankedwl'] = "#{summary["rankedStats"]["wins"]} : #{summary["rankedStats"]["losses"]}"
                @summoner_info[id]['normalWins'] = summary["normalStats"]["wins"]
            rescue NoMethodError
                flash[:errors] = "Info for some summoner names couldn't be found. Sorry!"
                @summoner_info.delete(id)
                next
            end
        end
        slim :dream_team
    end
end

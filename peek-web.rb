require 'sinatra'
require 'dotenv'
require 'json'
require 'net/http'
require 'slim'
require 'sinatra/reloader' if development?
Dotenv.load
$region = 'na' 
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

    def get_summoners_league_info(ids)
        path = "https://#{$region}.api.pvp.net/api/lol/#{$region}/v2.5/league/by-summoner/#{ids}/entry" + API_KEY_SUFFIX
        puts path
        result =JSON.parse(Net::HTTP.get(URI.parse(URI.encode(path))))
    end

    def get_summoner_summary(summoner_id)
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
    def get_stat_summary(summoner_id)
        summary = JSON.parse(Net::HTTP.get(URI.parse(URI.encode("https://#{$region}.api.pvp.net/api/lol/#{$region}/v1.3/stats/by-summoner/#{summoner_id}/summary" + API_KEY_SUFFIX))))
        res = {} 
        data = summary['playerStatSummaries']
        dupa = data.index{|c| c['playerStatSummaryType']=='RankedSolo5x5'}
        dupa2 = data.index{|c| c['playerStatSummaryType']=='Unranked'}
        res['rankedStats'] = data[dupa].select {|k,v| ['wins', 'losses'].include?(k)} if dupa
        res['normalStats'] = data[dupa2].select{|k,v| ['wins'].include?(k)} if dupa2
        res
    end

    def parse_names_from_params(chatlog, manual)
        names = []
        #TODO: think about recombining into one regexp
        names += chatlog.scan(/([A-Za-z0-9 ]+) joined the room/)
        chatlog.lines.each { |l| names << l.scan(/^([A-Za-z0-9 ]+):/) }
        names += manual.split(",").map(&:chomp)
        return names.flatten.uniq.to_ary
    end
    def parse_league_info(league_info_for_summoner)
        res = {}
        stat = league_info_for_summoner
        idx_5x5_solo = stat.index {|c| c['queue']=="RANKED_SOLO_5x5"}
        idx_5x5_team = stat.index {|c| c['queue']=="RANKED_TEAM_5x5"}
        res["rankedSoloLeague"] = stat[idx_5x5_solo].select {|k,v| ['tier', 'entries'].include?(k)} if idx_5x5_solo
        res["rankedTeamLeague"] = stat[idx_5x5_team].select{|k,v| ['tier', 'entries'].include?(k)} if idx_5x5_team

        res
    end

end
get '/' do
    slim :home
end
post '/' do
    $region = params['region']
    redirect '/' unless params['chatlog'] !="" || params['manualEntry'] != ""
    team = parse_names_from_params(params['chatlog'], params['manualEntry'])
    @summoner_info = {}
    id_info = get_summoner_info(team.join(", "))
    league_info = get_summoners_league_info(id_info.values.map{|i| i['id']}.join(", "))
    puts league_info
    team.each do |tm|
        id = id_info[tm.downcase.gsub(' ', '')]['id']
        @summoner_info[id] = {}
        @summoner_info[id]['name'] = tm
        # @summoner_info[id]['match_history'] = get_match_history(id)
        @summoner_info[id]['summary'] = get_stat_summary(id)
        @summoner_info[id]['leagues'] = parse_league_info(league_info[id.to_s])
    end
    slim :dream_team
end

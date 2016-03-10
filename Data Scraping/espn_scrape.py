import pandas as pd
import requests
from bs4 import BeautifulSoup
from sqlalchemy import create_engine
import subprocess
import time
import numpy as np
from datetime import datetime, date
import traceback
import re

__author__ = 'Ryan'

def main_team_list():
    conn = 'mysql+mysqlconnector://ptest:nimda1@localhost/stg'
    engine = create_engine(conn)

    # get list of teams names
    teams = get_team_list()
    teams.to_sql('stgteam',engine,index=False,if_exists="replace")


def main_games():
    conn = 'mysql+mysqlconnector://ptest:nimda1@localhost/stg'
    engine = create_engine(conn)

    # get list of game ids
    teams = pd.read_sql('stgteam',engine)
    years = list(range(2002, 2016))
    for year in years:
        print("start year " +str(year) + "\n"
              + time.strftime("%H:%M:%S",time.localtime()))
        games = get_game_results(teams,year)
        try:
            games.to_sql('stggames',engine,index = False ,if_exists="append"
                         ,chunksize = 20000)
        except Exception as e:
            restart_server()
            engine = create_engine(conn)
            games.to_sql('stggames',engine,index = False ,if_exists="append"
                         ,chunksize = 20000)
        print("finish" + "\n"
              + time.strftime("%H:%M:%S",time.localtime()))

def main_pbp():
    conn = 'mysql+mysqlconnector://ptest:nimda1@localhost/stg'
    engine = create_engine(conn)

    # get play by play
    n = 200  # number of games to add to pbp table before export
    sql = 'select * from play_by_play_missing'
    games = pd.read_sql(sql, engine)
    for l in list(range(1,len(games["match_id"]),n)):
        l_high = min(l+n,len(games["match_id"]))
        print("starting " + str(l) + " to " + str(l_high) + "\n"
              + time.strftime("%H:%M:%S",time.localtime()))
        playByPlay = get_play_by_play(games["match_id"][l:l_high])
        try:
            playByPlay.to_sql('stgplay_by_play' ,engine ,index = False,
                              if_exists = "append",chunksize=20000)
        except Exception as e:
            restart_server()
            engine = create_engine(conn)
            playByPlay.to_sql('stgplay_by_play' ,engine ,index = False
                              , if_exists = "append",chunksize=20000)
        print("finished - "+ time.strftime("%H:%M:%S",time.localtime()))

def main_box_score():
    conn = 'mysql+mysqlconnector://ptest:nimda1@localhost/stg'
    engine = create_engine(conn)
    n = 200
    sql = 'select * from stg.games_missing_all'
    games = pd.read_sql(sql, engine)
    s = requests.session()
    for l in list(range(0,len(games["match_id"]),n)):
        l_high = min(l+n,len(games["match_id"]))
        print("starting " + str(l) + " to " + str(l_high) + "\n"
               + time.strftime("%H:%M:%S",time.localtime()))
        players = get_player_box_score(games.iloc[l:l_high], s)
        try:
            players.to_sql('stgboxscore',engine,index = False
                           , if_exists = "append", chunksize = 20000)
        except Exception as e:
            restart_server()
            engine = create_engine(conn)
            players.to_sql('stgboxscore',engine,index = False
                           , if_exists = "append", chunksize = 20000)


def main_player():
    conn = 'mysql+mysqlconnector://ptest:nimda1@localhost/stg'
    engine = create_engine(conn)
    n = 1
    sql = 'select * from stg.view_box_players'
    players = pd.read_sql(sql, engine)
    s = requests.session()
    for idx, row in players.iterrows():
        if idx % n == 0:
            print(idx)
            if idx > 0:
                try:
                    plr.to_sql('stgbox_player',engine,index = False
                               , if_exists = "append", chunksize = 20000)
                except Exception as e:
                    restart_server()
                    engine = create_engine(conn)
                    players.to_sql('stgbox_player',engine,index = False
                                   , if_exists = "append", chunksize = 20000)
            plr = get_player(row[1], row[0])
        else:
            plr = plr.append(get_player(row[1], row[0])
                             , ignore_index = True)
    try:
        plr.to_sql('stgbox_player',engine,index = False
                   , if_exists = "append", chunksize = 20000)
    except Exception as e:
        restart_server()
        engine = create_engine(conn)
        players.to_sql('stgbox_player',engine,index = False
                       , if_exists = "append", chunksize = 20000)


def get_team_list():
    url = 'http://espn.go.com/nba/teams'
    r = requests.get(url)

    soup = BeautifulSoup(r.text)
    tables = soup.find_all('ul', class_='medium-logos')

    teams = []
    prefix_1 = []
    prefix_2 = []
    teams_urls = []
    for table in tables:
        lis = table.find_all('li')
        for li in lis:
            info = li.h5.a
            teams.append(info.text)
            url = info['href']
            teams_urls.append(url)
            prefix_1.append(url.split('/')[-2])
            prefix_2.append(url.split('/')[-1])
    dic = {'url': teams_urls, 'prefix_2': prefix_2, 'prefix_1': prefix_1
        , 'team': teams}
    teams = pd.DataFrame(dic, index=teams)
    teams.index.name = 'team'
    return(teams)

def get_game_results(teams,year):
    BASE_URL = 'http://espn.go.com/nba/team/schedule/_/name/{0}/year/{1}' \
               '/seasontype/3/{2}'
    match_id = []
    dates = []
    home_team = []
    home_team_score = []
    visit_team = []
    visit_team_score = []
    for index, row in teams.iterrows():
        _team, url = row['team'], row['url']
        r = requests.get(BASE_URL.format(row['prefix_1'], year
                                         , row['prefix_2']))
        table = BeautifulSoup(r.text).table
        try:
            for row in table.find_all('tr'):
                try:
                    columns = row.find_all('td')
                    _home = True if columns[1].li.text == 'vs' else False
                    _other_team = columns[1].find_all('a')[1].text
                    _score = columns[2].a.text.split(' ')[0].split('-')
                    _won = True if columns[2].span.text == 'W' else False
                    d = datetime.strptime(columns[0].text + " " +str(year)
                                          , '%a, %b %d %Y')
                    if d.month >= 10:
                        year_season = year-1
                    else:
                        year_season = year

                    match_id.append(columns[2].a['href'].split('?id=')[1])
                    home_team.append(_team if _home else _other_team)
                    visit_team.append(_team if not _home else _other_team)
                    dates.append(date(year_season, d.month, d.day))

                    if _home:
                        if _won:
                            home_team_score.append(_score[0])
                            visit_team_score.append(_score[1])
                        else:
                            home_team_score.append(_score[1])
                            visit_team_score.append(_score[0])
                    else:
                        if _won:
                            home_team_score.append(_score[1])
                            visit_team_score.append(_score[0])
                        else:
                            home_team_score.append(_score[0])
                            visit_team_score.append(_score[1])
                except Exception as e:
                        pass
        except Exception as e:
            pass # Not all columns row are a match, is OK
            # print(e)

    dic = {'id': match_id, 'date': dates, 'home_team': home_team
        , 'visit_team': visit_team
        ,'home_team_score': home_team_score
        , 'visit_team_score': visit_team_score,'match_id': match_id}

    games = pd.DataFrame(dic).drop_duplicates(subset='id').set_index('id')
    return(games)

def get_play_by_play(match_id):
    BASE_URL = 'http://espn.go.com/nba/playbyplay?gameId={0}&period={1}'

    game_time = []
    home_action = []
    home_team_score = []
    visit_team_score = []
    visit_action = []
    match_id_rep = []
    qtr_rep = []

    for id in match_id:
        qtr = 1
        try:
            r = requests.get(BASE_URL.format(id,0))
        except Exception as e:
            #print(e.with_traceback())
            print("Connection Refused")
            print(time.strftime("%H:%M:%S",time.localtime()))
            time.sleep(1800)
            r = requests.get(BASE_URL.format(id,0))
        soup = BeautifulSoup(r.text)
        table = soup.find('table',attrs = {'class':'mod-data'})
        try:
            for row  in table.find_all('tr'):
                cols = row.find_all('td')
                cols = [ele.text.strip() for ele in cols]
                if len(cols) == 4:
                    _score = cols[2].split(' ')[0].split('-')
                    game_time.append(datetime.strptime(cols[0],'%M:%S'))
                    home_action.append(cols[1])
                    home_team_score.append(_score[0])
                    visit_team_score.append(_score[1])
                    visit_action.append(cols[3])
                    match_id_rep.append(id)
                    if game_time[len(game_time)-2] < game_time[len(game_time)-1]:
                        qtr = qtr + 1
                    qtr_rep.append(qtr)
        except Exception as e:
            print(id)
            pass
    dic = {'match_id': match_id_rep, 'qtr':qtr_rep, 'game_time' : game_time
        , 'home_action': home_action, 'visit_action': visit_action
        , 'home_team_score': home_team_score
        , 'visit_team_score': visit_team_score}
    playByPlay = pd.DataFrame(dic)
    return(playByPlay)

def get_player_box_score(games, ses):
    BASE_URL = 'http://espn.go.com/nba/boxscore?gameId={0}'
    r = ses.get(BASE_URL.format(games.iloc[0]['match_id']))
    first_cookies = r.cookies
    soup = BeautifulSoup(r.text)
    table = soup.find('table',attrs = {'class':'mod-data'})
    heads = table.find_all('thead')
    headers = heads[0].find_all('tr')[0].find_all('th')[1:]
    headers = [th.text for th in headers]
    columns = ['id', 'team', 'starter', 'player', 'position', 'url'] + headers
    players = pd.DataFrame(columns=columns)
    for index in games['match_id']:
        try:
            r = ses.get(BASE_URL.format(index), cookies = first_cookies)
        except Exception as e:
            print("connection refused")
            time.sleep(120)
            try:
                r = ses.get(BASE_URL.format(index), cookies = first_cookies)
            except Exception:
                return(players)
            pass
        soup = BeautifulSoup(r.text)
        try:
            table = soup.find_all('table',attrs = {'class':'mod-data'})
            teams = soup.find_all('span', attrs = {'class':'team-name'})
            bodies = table[0].find_all('tbody')


            team_1 = teams[0].text
            team_1_players = bodies[0].find_all('tr')
            team_1_players = get_player_box_score_helper(team_1_players
                                                         , 'STARTER'
                                                         , team_1, headers
                                                         , columns, index)
            players = players.append(team_1_players)
            team_1_players = bodies[1].find_all('tr')
            team_1_players = team_1_players[:len(team_1_players) - 2]
            team_1_players = get_player_box_score_helper(team_1_players
                                                         , 'BENCH'
                                                         , team_1, headers
                                                         , columns, index)
            players = players.append(team_1_players)

            bodies = table[1].find_all('tbody')
            team_2 = teams[1].text
            team_2_players = bodies[0].find_all('tr')
            team_2_players = get_player_box_score_helper(team_2_players
                                                         , 'STARTER'
                                                         , team_2
                                                         , headers, columns
                                                         , index)
            players = players.append(team_2_players)
            team_2_players = bodies[1].find_all('tr')
            team_2_players = team_2_players[:len(team_2_players) - 2]
            team_2_players = get_player_box_score_helper(team_2_players
                                                         , 'BENCH'
                                                         , team_2
                                                         , headers, columns
                                                         , index)
            players = players.append(team_2_players)
        except Exception as e:
            print(traceback.format_exc())
            print(index)
            urls = ['http://espn.go.com/mlb/team/_/name/bal/baltimore-orioles'
                    , 'http://espn.go.com/'
                    , 'http://espn.go.com/nba/team/_/name/gs/golden-state-warriors'
                    , 'http://www.espnfc.us/scores'
                    , 'http://espn.go.com/nfl/schedule'
                    , 'http://espn.go.com/nba/schedule'
                    , 'http://espn.go.com/nba/statistics'
                    , 'http://espn.go.com/espn/news/story?id=5630562']
            time.sleep(np.random.randint(1,60))
            ses = requests.session()
            r = ses.get(urls[np.random.randint(0,len(urls))])
            r = ses.get(urls[np.random.randint(0,len(urls))])
            first_cookies = r.cookies
            pass

    return(players)

def get_player_box_score_helper(players, starter, team_name, headers, columns, index):
    array = np.zeros((len(players), len(headers)+3), dtype=object)
    array[:] = np.nan
    for i, player in enumerate(players):
        try:
            cols = player.find_all('td')
            array[i, 0] = cols[0].text[:len(cols[0].text) - 2]
            array[i, 1] = cols[0].text[len(cols[0].text) - 2:]
            array[i, 2] = cols[0].a['href']
            for j in range(3, len(headers) + 3):
                if not (cols[1].text.startswith('Did not play') or
                cols[1].text.startswith('DNP')):
                    array[i, j] = cols[j - 2].text
        except Exception as e:
            print('match_id: ' + str(index) + '\n' + 'player: '
              + str(cols[0].text) + '\n' + team_name + ' ' + starter
              +'\n' 'index: ' + str(i))
            print(cols[0].text)
            print(cols[j - 2].text)
    frame = pd.DataFrame(columns=columns)
    for x in array:
        line = np.concatenate(([index, team_name, starter], x)).reshape(1,len(columns))
        new = pd.DataFrame(line, columns=frame.columns)
        frame = frame.append(new)
    return frame

def get_player(player_url, box_name):
    r = requests.get(player_url)
    soup = BeautifulSoup(r.text)
    try:
        table = soup.find_all('ul',attrs = {'class':'general-info'})
        cols = table[0].find_all('li')
        hw = re.sub("[^0-9,:']", "",cols[1].text).split(",")
        height = hw[0].split("'")
        height = int(height[0])*12 + int(height[1])
        weight = int(hw[1])
        player_name = soup.find('h1').text
        table = soup.find_all('ul',attrs = {'class':'player-metadata floatleft'})
        for idx, col in enumerate(table):
            if idx == 0:
                cols = col.find_all('li')
            else:
                cols = cols + col.find_all('li')
        bdate = cols[0].text.replace('Born','')
        if bdate.find('in') > 0:
            bdate = bdate[:bdate.find('in')-1]
        else:
            bdate = bdate[:bdate.find('(Age:')-1]
        bdate = datetime.strptime(bdate[:12], '%b %d, %Y').strftime('%Y-%m-%d')
        if 'Died' in cols[1].text:
            cols = [cols[0]] + cols[2:]
        if 'Drafted' in cols[1].text:
            draft = re.sub("[^0-9,:]", "",cols[1].text)
            draft_year = draft[:draft.find(':')]
            draft_rnd = draft[draft.find(':')+1:draft.find(',')]
            draft_num = draft[draft.find(',')+1:]
            draft_team = cols[1].text[cols[1].text.find('by')+3:]
            college = cols[2].text.replace('College', '')
            try:
                experience = cols[3].text.replace('Experience', '')
                experience = int(experience.replace('year', '').replace('s',''))
            except IndexError:
                experience = -1
        else:
            draft_year = -1
            draft_rnd = -1
            draft_num = -1
            draft_team = ''
            college = cols[1].text.replace('College', '')
            try:
                experience = cols[2].text.replace('Experience', '')
                experience = int(experience.replace('year', '').replace('s',''))
            except IndexError:
                experience = -1
    except Exception as e:
        print(traceback.format_exc())
        print('URL: ' + player_url)
        #print(cols)
        return
    dic = {'player': player_name, 'player_lname': box_name, 'bdate': bdate
           , 'draft_year': draft_year, 'draft_rnd': draft_rnd
           , 'draft_num': draft_num, 'draft_team': draft_team
           , 'college': college, 'exp': experience
           , 'height': height, 'weight': weight
           , 'url': player_url}
    plr = pd.DataFrame(dic, index = [0])
    return(plr)


def restart_server():
    try:
        subprocess.call("NET STOP MySQL")
    except Exception as e:
        pass
    subprocess.call("NET START MySQL")


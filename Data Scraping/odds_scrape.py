__author__ = 'Ryan'

import pandas as pd
import requests
from bs4 import BeautifulSoup
from sqlalchemy import create_engine
import subprocess
import time
import numpy as np
from datetime import datetime, date

def main_odds_team():
    conn = 'mysql+mysqlconnector://ptest:nimda1@localhost/stg'
    engine = create_engine(conn)
    teams = get_odds_team()
    teams.to_sql('team_odds',engine,index=False,if_exists="replace")

def main_odds_results():
    conn = 'mysql+mysqlconnector://ptest:nimda1@localhost/stg'
    engine = create_engine(conn)
    team_odds = pd.read_sql('select team_odd_id from team_odds', engine)
    team_odds = team_odds['team_odd_id']
    for team in team_odds:
        for yr in range(2003, 2016):
            season_results = get_odds_results(team, yr)
            season_results.to_sql('stgteam_odds_result',engine,index=False
                                  , if_exists="append")
            print("Extracted Team: ")
            print(team)
            print(" Yr: ")
            print(yr)



def get_odds_team():
    url = 'http://www.covers.com/pageLoader/pageLoader.aspx?page=/data/nba/ ' \
          'teams/teams.html'
    r = requests.get(url)

    soup = BeautifulSoup(r.text)
    tables = soup.find_all('td', class_='datacell')

    teams = []
    team_odd_id = []
    for table in tables:
        lis = table.find_all('a', href = True)
        for li in lis:
            url = li['href']
            teams.append(li.text)
            team_odd_id.append(url[url.find('/team')+11:len(url)-5])
    dic = {'team_odd_id': team_odd_id, 'team': teams}
    teams_odd = pd.DataFrame(dic, index=teams)
    teams_odd.index.name = 'team'
    return(teams_odd)

def get_odds_results(team_odd_id, year):
    BASE_URL = 'http://www.covers.com/pageLoader/pageLoader.aspx?page=/ ' \
               'data/nba/teams/pastresults/{0}/team{1}.html'
    season_year = str(year-1) + "-" + str(year)
    try:
        r = requests.get(BASE_URL.format(season_year, team_odd_id))
    except Exception as e:
        print(e)
        print("Connection Refused")
        print(time.strftime("%H:%M:%S",time.localtime()))
        time.sleep(1800)
        r = requests.get(BASE_URL.format(season_year, team_odd_id))

    soup = BeautifulSoup(r.text)
    tables = soup.find_all("table", attrs={'class':'data'})

    team_id = []
    opp_id = []
    opp_name = []
    game_date = []
    home = []
    result = []
    pts = []
    opp_pts = []
    ot = []
    game_type = []
    line_wl =[]
    line = []
    ou = []
    ou_pts =[]
    for table in tables:
        for row in table.find_all('tr'):
            try:
                cols = row.find_all('td')
                col_txt = [c.text.strip().replace('\r\n','') for c in cols]
                url = cols[1].find_all('a', href = True)[0]['href']
                dash = col_txt[2].find('-')
                team_id.append(team_odd_id)
                opp_id.append(url[url.find('/team')+11:len(url)-5])
                opp_name.append(col_txt[1].replace('@', '').strip())
                game_date.append(col_txt[0])
                home.append(col_txt[1].find('@') * -1)
                result.append(col_txt[2][:1])
                pts.append(col_txt[2][dash - 3:dash].strip())
                opp_pts.append(col_txt[2][dash + 1:].replace('(OT)',''))
                ot.append(1 * (col_txt[2].find('(OT)') > 0))
                game_type.append(col_txt[3])
                line_wl.append(col_txt[4][:1])
                line.append(col_txt[4][1:].strip())
                ou.append(col_txt[5][:1])
                ou_pts.append(col_txt[5][1:].strip())
            except Exception as e:
                print(e)
                pass
    dic = {'team_odd_id': team_id, 'opp_odd_id': opp_id, 'opp_name': opp_name
           , 'game_date': game_date, 'home': home, 'result': result
           , 'pts': pts, 'opp_pts': opp_pts, 'ot': ot, 'game_type': game_type
           , 'line_wl': line_wl, 'line': line, 'ou': ou, 'ou_pts': ou_pts}
    season_results = pd.DataFrame(dic)
    return(season_results)



main_odds_results()
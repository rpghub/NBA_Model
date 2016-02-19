
data {
  int<lower=0> N_roster;
  int<lower=0> N;
  int<lower=0> y[N]; 
  int<lower=0> roster[N];
  int<lower=0> opp_roster[N];
  int<lower=0> home[N];
  real<lower=0> pos[N];
  int<lower=0> rest[N];
  // out of sample prediction data
  int<lower=0> N_new; 
  int<lower=0> roster_new[N_new];
  int<lower=0> opp_roster_new[N_new];
  int<lower=0> home_new[N_new];
  real<lower=0> pos_new[N_new];
  int<lower=0> rest_new[N_new];
} 
parameters {
  real o_roster[N_roster];
  real d_roster[N_roster];
  real <lower=0> a_roster;
  real alpha;
  real beta;
  real beta_rest[3];
}
transformed parameters {
  real theta[N]; 
  for (i in 1:N){
    theta[i] <- o_roster[roster[i]] - d_roster[opp_roster[i]] + alpha * home[i] + log(pos[i]) + 
                  beta + beta_rest[rest[i]];
  }
}
model {
  // roster estimates based on team priors
  a_roster ~ gamma(.01, 100);
  o_roster ~ normal(0, a_roster);
  d_roster ~ normal(0, a_roster);

  // home field param
  alpha ~ normal(0, 100);
  beta ~ normal(0, 100);
  beta_rest ~ normal(0, .025);
  //final fit
  y ~ poisson_log(theta);
}
generated quantities { 
  int<lower=0> y_sim[N];
  int<lower=0> y_new[N_new];
  for (i in 1:N){
    y_sim[i] <- poisson_log_rng(theta[i]);
  }

  for (i in 1:N_new){
    y_new[i] <- poisson_log_rng(o_roster[roster_new[i]] - d_roster[opp_roster_new[i]] 
                               + alpha * home_new[i] + log(pos_new[i]) + beta 
                               + beta_rest[rest_new[i]]);
  }
}
require("pacman")
pacman::p_load("stringr","Hmisc","stats","readxl","data.table","zoo")

setwd("Z://5_Gestion_Financiere/5.1_RESU-BDF/SIMU_BDF/Strat�gie 2022/CAP_juillet_2022/projections_stochastiques/EURUSD")

##########################################   DOWNLOAD DATA    ##########################################

#1. Options prices
options<-as.data.frame(read_excel("UEA_options.xlsx",1))                                   #upload data
colnames(options)[c(1,5,8,12)]<-c("call strike","call price","put strike","put price")     #rename columns
options<-options[,colnames(options)%in%c("call strike","call price","put strike","put price")]                                                   #remove columns

#get options maturities
options$`call price`[is.na(options$`call price`)]<-
  options$`put price`[is.na(options$`put price`)]<-"matu"     #identify new series
mat<-which(is.na(as.numeric(options$`call strike`)))[-1]      #identify lines with a new option maturity
matu<-word(options$`call strike`[mat],1,3)                    #the associated option maturity
terms<-as.numeric(gsub('[^0-9.-]','',word(matu,2)))/365       
mat<-c(mat,nrow(options))                                     #add one last term to mat for the loop

#graph option prices for the most remote maturity
graph<-cbind(options$`call strike`,options$`call price`, options$`put price`)
graph<-apply(graph,2,as.numeric)
graph<-graph[last(which(is.na(graph[,1]))):nrow(graph),]

cex<-0.8
col<-c("lightblue","indianred")
par(mar=c(6,4,4,4) + 0.1, xpd=T, cex.axis=cex)
plot(graph[,1:2],xlim=range(graph[,1],na.rm=T),ylim=range(graph[,2:3],na.rm=T),col=col[1],type="l",
     main=paste(word(last(matu),1),"EURUSD put and call prices for traded strikes, 10/07/2022",sep=" "),
     pch=20,xlab="",ylab="option premium (EUR)")
lines(graph[,c(1,3)], col=col[2])
title(xlab="strike price (EUR)",adj=1)
legend("bottom", horiz=T, bty="n",inset=c(-0.05,-0.35),legend=c("calls","puts"),lty=1,text.col=col,col=col)

#2. Futures prices at options' maturities
fut<-as.data.frame(do.call(rbind,strsplit(word(options$`call strike`[nchar(options$`call strike`)>20],-2,-1)," ")))
fut[,2]<-as.numeric(fut[,2])

#3. Riskfree rates at options' maturities
rates<-as.data.frame(read_excel("EUR_rates.xlsx"))                      #taux d'actualisation des prix d'options
rates<-rates[rates$YLD_YTM_MID!="#N/A Invalid Security",]
rates$MATURITY<-as.Date(rates$MATURITY, format = "%d/%m/%Y")
rates$terms<-as.numeric((rates$MATURITY-as.Date("2022-10-07"))/365)
rates<-as.data.frame(apply(rates,2,as.numeric))

#get by extrapolation a risk free rate for each option maturity
rates_n<-list()
for (i in 1:length(terms)){
  rates_n[[i]]<-approxExtrap(rates$terms, rates$YLD_YTM_MID, xout=terms[i], method = "linear",
                             n = 50, rule = 2, f = 0, ties = "ordered", na.rm = FALSE)$y}
rates_n<-unlist(rates_n)/100

###############################  CALIBRATION OF PARAMETERS  ##########################################

#European call price, put price, and expected spot price for a sum of 2 lognormals in the Black & Scholes model
#r,T,FWD ne sont pas d�clar�s comme variables car pour chaque terme dans la boucle ils sont fixes
CALLE_M<-function(x,KC){
  d1_C<-(x[1]+x[3]^2-log(KC))/x[3]
  d2_C<-(x[1]-log(KC))/x[3]   # d2_C<-d1_C-x[3]
  d3_C<-(x[2]+x[4]^2-log(KC))/x[4]
  d4_C<-(x[2]-log(KC))/x[4]   # d4_C<-d1_C-x[4]
  CALL1<-exp(-r*T)*(exp(x[1]+(x[3]^2/2))*pnorm(d1_C)-KC*pnorm(d2_C))
  CALL2<-exp(-r*T)*(exp(x[2]+(x[4]^2/2))*pnorm(d3_C)-KC*pnorm(d4_C))
  CALLE_M<-x[5]*CALL1+(1-x[5])*CALL2
  return(CALLE_M)
}

PUTE_M<-function(x,KP){
  PUTE_M<-CALLE_M(x,KP)+exp(-r*T)*(KP-FWD)     #put call parity
  return(PUTE_M)}

ESP_M<-function(x){                           #expected value for a lognormal distributuion
  ESP_M<-x[5]*exp(x[1]+(x[3]^2/2))+(1-x[5])*exp(x[2]+(x[4]^2/2))
  return(ESP_M)}

#Function to minimize for 7 parameters
MSE<-function(x){
  C_INF<-pmax(ESP_M(x)-KC,CALLE_M(x,KC))
  C_SUP<-exp(r*T)*CALLE_M(x,KC)
  P_INF<-pmax(KP-ESP_M(x),PUTE_M(x,KP))
  P_SUP<-exp(r*T)*PUTE_M(x,KP)
  A<-as.numeric(KC<=ESP_M(x))
  B<-as.numeric(KP>=ESP_M(x))
  w_call<-A*x[6]+(1-A)*x[7]
  w_put<-B*x[6]+(1-B)*x[7]
  CALL<-w_call*C_INF+(1-w_call)*C_SUP
  PUT<-w_put*P_INF+(1-w_put)*P_SUP
  RES_C<-sum((C-CALL)^2, na.rm=T)
  RES_P<-sum((P-PUT)^2, na.rm=T)
  RES_F<-(FWD-ESP_M(x))^2
  MSE<-RES_C+RES_P+RES_F
  return(MSE)
}

#weights on itm and otm options fixed for the moment at 0.5 each thus 1st optim on first 5 parameters
PR<-seq(0.1,0.49,0.01)

objective<-function(x){
  objective<-MSE(c(x[1:4],PR[i],0.5,0.5))
}

#Calibration of the 7 parameters using market data
params<-CV<-list()

for (m in 1:length(terms)){
  
  T<-terms[m]                                     #maturity m
  r<-rates_n[m]                                   #discount rate for maturity m
  prices<-options[mat[m]:mat[m+1],c(1,2,4)]       #prices of options for maturity m
  prices<-na.omit(apply(prices,2,as.numeric))
  C<-prices[,2]                                   #prices of calls
  P<-prices[,3]                                   #prices of puts
  KC<-KP<-prices[,1]                              #strikes of puts and calls
  FWD<-fut[m,2]                                   #future price for maturity m
  
  #1st optimization over 6 parameters to get initialization values for second optim
  PARA<-matrix(nrow=length(PR),ncol=8,dimnames=
                 list(c(),c(paste0("m",seq(2)),paste0("s",seq(2)),"p",paste0("w",seq(2)),"SCE")))
  start<-rep(c(log(FWD),0.2),each=2)
  lower<-rep(c(-10,1e-6),each=2)
  upper<-rep(c(10,0.9),each=2)
  
  for (i in 1:length(PR)){
    sol<-nlminb(start=start,objective=objective,lower=lower, upper = upper, control=list(iter.max=500))
    PARA[i,1:4]<-sol$par[1:4]
    PARA[i,5]<-PR[i]
    PARA[i,8]<-sol$objective
  }
  PARA[,6:7]<-0.5
  
  param<-PARA[which.min(PARA[,8]),-8]
  
  #2nd optimization over 8 parameters
  param[param==0]<-1e-6
  
  L<-U<-rep(0,length(param))
  L[sign(param)==-1]<-2*param[sign(param)==-1]
  L[sign(param)==1]<-1e-2*param[sign(param)==1]
  U[sign(param)==-1]<-1e-2*param[sign(param)==-1]
  U[sign(param)==1]<-2*param[sign(param)==1]
  CI<-c(L,-U)
  UI<-rbind(diag(length(L)),-diag(length(L)))
  
  solu<-constrOptim(param,MSE,NULL,ui=UI,ci=CI,mu=1e-05,control=list(iter.max=2000),method="Nelder-Mead")$par
  
  CV[[m]]<-constrOptim(param,MSE,NULL,ui=UI,ci=CI,mu=1e-05,control=list(iter.max=2000),method="Nelder-Mead")$convergence
  
  params[[m]]<-c(log(FWD)+(solu[1:2]-log(FWD))/T, solu[3:4]/sqrt(T), solu[5])
}

#European call price, put price, and expected spot price for a sum of 3 lognormals in the Black & Scholes model
CALLE_M<-function(x,KC){
  d1_C<-(x[1]+x[4]^2-log(KC))/x[4]
  d2_C<-(x[1]-log(KC))/x[4]   # d2_C<-d1_C-x[4]
  d3_C<-(x[2]+x[5]^2-log(KC))/x[5]
  d4_C<-(x[2]-log(KC))/x[5]   # d4_C<-d3_C-x[5]
  d5_C<-(x[3]+x[6]^2-log(KC))/x[6]
  d6_C<-(x[3]-log(KC))/x[6]   # d6_C<-d5_C-x[6]
  CALL1<-exp(-r*T)*(exp(x[1]+(x[4]^2/2))*pnorm(d1_C)-KC*pnorm(d2_C))
  CALL2<-exp(-r*T)*(exp(x[2]+(x[5]^2/2))*pnorm(d3_C)-KC*pnorm(d4_C))
  CALL3<-exp(-r*T)*(exp(x[3]+(x[6]^2/2))*pnorm(d5_C)-KC*pnorm(d6_C))
  CALLE_M<-x[7]*CALL1+x[8]*CALL2+(1-x[7]-x[8])*CALL3
  return(CALLE_M)
}

PUTE_M<-function(x,KP){
  PUTE_M<-CALLE_M(x,KP)+exp(-r*T)*(KP-FWD)
  return(PUTE_M)}

ESP_M<-function(x){
  ESP_M<-x[7]*exp(x[1]+(x[4]^2/2))+x[8]*exp(x[2]+(x[5]^2/2))+(1-x[7]-x[8])*exp(x[3]+(x[6]^2/2))
  return(ESP_M)}

#function to minimize over 10 parameters
MSE<-function(x){
  C_INF<-pmax(ESP_M(x)-KC,CALLE_M(x,KC))
  C_SUP<-exp(r*T)*CALLE_M(x,KC)
  P_INF<-pmax(KP-ESP_M(x),PUTE_M(x,KP))
  P_SUP<-exp(r*T)*PUTE_M(x,KP)
  A<-as.numeric(KC<=ESP_M(x))
  B<-as.numeric(KP>=ESP_M(x))
  w_call<-A*x[9]+(1-A)*x[10]
  w_put<-B*x[9]+(1-B)*x[10]
  CALL<-w_call*C_INF+(1-w_call)*C_SUP
  PUT<-w_put*P_INF+(1-w_put)*P_SUP
  RES_C<-sum((C-CALL)^2, na.rm=T)
  RES_P<-sum((P-PUT)^2, na.rm=T)
  RES_F<-(FWD-ESP_M(x))^2
  MSE<-RES_C+RES_P+RES_F
  return(MSE)
}

#weights on itm and otm options fixed for the moment at 0.5 each thus 1st optim on 8 parameters
PR<-seq(0.1,1,0.01)                  #possible weights on the first two lognormals
PR<-expand.grid(c(rep(list(PR),2)))
PR<-PR[rowSums(PR)<0.9,]

objective<-function(x){
  objective<-MSE(c(x[1:6],PR[i,1],PR[i,2],0.5,0.5))
}

params<-CV<-list()

#optimization
for (m in 1:length(terms)){
  
  prices<-options[mat[m]:mat[m+1],c(1,2,4)]
  prices<-na.omit(apply(prices,2,as.numeric))/100
  C<-prices[,2]                                   #prices of calls, expressed in % of par, so not to be divided by 100
  P<-prices[,3]                                   #prices of puts
  KC<-KP<-prices[,1]                              #strikes of puts and calls
  FWD<-fut[m,2]/100
  T<-terms[m]
  r<-rates_n[m]
  
  ##Thus 1st optimization over first 8 parameters to get initialization values for second optim
  PARA<-matrix(nrow=nrow(PR),ncol=12,dimnames=
                 list(c(),c(paste0("m",seq(3)),paste0("s",seq(3)),paste0("p",seq(2)),paste0("w",seq(2)),"p1+p2","SCE")))
  lower<-rep(c(-10,1e-6),each=3)
  upper<-rep(c(10,0.8),each=3)
  start<-rep(c(log(FWD),0.2),each=3)
  
  for (i in 1:nrow(PR)){
    sol<-nlminb(start=start,objective=objective,lower=lower, upper = upper, control=list(iter.max=500))
    PARA[i,1:6]<-sol$par[1:6]
    PARA[i,7]<-PR[i,1]
    PARA[i,8]<-PR[i,2]
    PARA[i,11]<-PR[i,1]+PR[i,2]
    PARA[i,12]<-sol$objective
  }
  PARA[,9:10]<-0.5
  
  param<-PARA[which.min(PARA[,12]),-12]
  
  #2nd optimization over 10 parameters
  param[param==0]<-1e-6
  
  L<-U<-rep(0,length(param))
  L[sign(param)==-1]<-2*param[sign(param)==-1]
  L[sign(param)==1]<-1e-2*param[sign(param)==1]
  U[sign(param)==-1]<-1e-2*param[sign(param)==-1]
  U[sign(param)==1]<-2*param[sign(param)==1]
  CI<-c(L,-U)
  UI<-rbind(diag(length(L)),-diag(length(L)))
  
  solu<-constrOptim(param,MSE,NULL,ui=UI,ci=CI,mu=1e-05,control=list(iter.max=2000),method="Nelder-Mead")$par
  
  CV[[m]]<-constrOptim(param,MSE,NULL,ui=UI,ci=CI,mu=1e-05,control=list(iter.max=2000),method="Nelder-Mead")$convergence
  
  params[[m]]<-c(log(FWD)+(solu[1:3]-log(FWD))/T, solu[4:6]/sqrt(T), solu[7:8])
}

###############################  GRAPH OF RISK NEUTRAL DENSITIES########################################

#Values of the densities
range_px<-c(0.5,1.3)*range(as.numeric(options$`call strike`),na.rm=T)
PX<-seq(range_px[1],range_px[2],10e-5)                                  #prices to compute PDF and CDF
params<-do.call(rbind,params)

#Probability Density Function for any maturity for a sum of 2 or 3 lognormals
PDF<-function(x){
  if(ncol(params)!=5){
    return(x[7]*dlnorm(PX,meanlog=x[1], sdlog=x[4]) + x[8]*dlnorm(PX,meanlog=x[2], sdlog=x[5])+
             (1-x[7]-x[8])*dlnorm(PX,meanlog=x[3], sdlog=x[6]))}
  else {return(x[5]*dlnorm(PX,meanlog=x[1], sdlog=x[3]) + (1-x[5])*dlnorm(PX,meanlog=x[2], sdlog=x[4]))}
}

DNR<-apply(params,1,PDF)
colSums(apply(DNR,2,rollmean,2)*diff(PX))    #check that integral of PDF*dPX is worth 1

#Graph of risk neutral densities for EURUSD future prices
co<-rainbow(length(matu))
xlim<-range(PX)
ylim<-range(DNR)
series_1<-apply(replicate(length(matu),PX),2,list)
series_2<-apply(DNR,2,list)
series<-lapply(seq_along(series_1), function(x) cbind(unlist(series_1[[x]]), unlist(series_2[[x]])))

cex<-0.8
par(mar=c(8,4,4,4) + 0.1, xpd=T,cex.axis=cex)
plot(NA,pch=20,xlab="",ylab="density",main="RNDs from a mixture of 3 lognormals",xlim=xlim,ylim=ylim,las=1)
mapply(lines,series,col=co)
title(sub="EURUSD future price",adj =1,line=2)
legend("bottom", inset=c(-0.05,-0.4), legend=word(matu,1), ncol=6,col=co, lty=1, bty="n")

#Cumulative Density Function for any maturity for a sum of 2 or 3 lognormals
CDF<-function(x){
  if(ncol(params)!=5){
    return(x[7]*plnorm(PX,meanlog=x[1], sdlog=x[4]) + x[8]*plnorm(PX,meanlog=x[2], sdlog=x[5])+
             (1-x[7]-x[8])*plnorm(PX,meanlog = x[3], sdlog = x[6]))}
  else {return(x[5]*plnorm(PX,meanlog=x[1], sdlog=x[3])+(1-x[5])*plnorm(PX,meanlog=x[2], sdlog=x[4]))}
}  

#Graph of cumulative density functions for rates
NCDF<-apply(params,1,CDF)
series_2_CDF<-apply(NCDF,2,list)
series_CDF<-lapply(seq_along(series_1), function(x) cbind(unlist(series_1[[x]]), unlist(series_2_CDF[[x]])))

par(mar=c(8,6,4,4) + 0.1, xpd=T, cex.axis=cex)
plot(NA, pch=20,xlab="",ylab="cumulative probability",las=1,main="RNDs from a mixture of 2 lognormals",xlim=xlim,ylim=0:1)
mapply(lines,series_CDF,col=co)
title(sub="EURUSD future price",adj =1,line=2)
legend("bottom", inset = c(-0.05,-0.5), legend = word(matu,1), ncol=5,col=co, lty = 1, bty = "n")

#mean, standard deviation, skewness, kurtosis and mode for the distribution at each options' maturity
E<-colSums(apply(PX*DNR,2,rollmean,k=2)*diff(PX))
dist_mean<-replicate(length(matu),PX)-t(replicate(nrow(DNR),E))
moments<-function(x){
  return(colSums(apply(dist_mean^x*DNR,2,rollmean,k=2)*diff(PX)))}
SD<-sqrt(moments(2))
SK<-moments(3)/SD^3
KU<-moments(4)/SD^4
mode<-PX[apply(DNR,2,which.max)]

#a few quantiles
thres<-rev(c(1,5,25,50,75,95,99)/100)
quantiles<-list()
for (i in 1:nrow(params)){
  quantiles[[i]]<-list()
  for (j in 1:length(thres)){
    quantiles[[i]][[j]]<-mean(PX[c(min(which(NCDF[,i]>thres[j]-0.01)),max(which(NCDF[,i]<thres[j]+0.01)))]) 
  }
  quantiles[[i]]<-unlist(quantiles[[i]])
}
quantiles<-as.data.frame(cbind(terms,do.call(rbind,quantiles)))
colnames(quantiles)<-c("term",paste0("q",100*thres))

#illustration #1: quantiles
colors<-c("#FF0000A0", "white", "#0000FFA0")
par(mar=c(8,4,4,4) + 0.1, xpd=T,cex.axis=cex)
plot(PX,DNR[,7], xlab="EURUSD future price",ylab="density",type="l",xlim=xlim,
     ylim=range(DNR[,7]),las=1, main=paste(word(matu[7],1), "RND from a mixture of 2 lognormals",sep=" "))
polygon(c(PX[PX>=quantiles$q75[7]], max(PX), quantiles$q75[7]),c(DNR[PX>=quantiles$q75[7],7], 0, 0), col=colors[3], border=colors[3])
polygon(c(quantiles$q5[7], min(PX), PX[PX<=quantiles$q5[7]]),c(0, 0, DNR[PX<=quantiles$q5[7],7]), col=colors[1], border=colors[1])
legend("bottom", horiz = T, inset = -0.4, title="Probability", legend = c("(0, 0.05]", "(0.05, 0.75]", "(0.75, 1]"), fill=colors, bty = "n")

#illustration #2: proba associated to a quantile
par(mar=c(8,4,4,4) + 0.1, xpd=T,cex.axis=cex)
q<-c(1.00,1.15)          #we define two quantiles of interest
plot(PX,DNR[,7], xlab="EURUSD future price",ylab="density",type="l",xlim=xlim, ylim=range(DNR[,7]),las=1,
     main=paste(word(matu[7],1), "RND from a mixture of 2 lognormals",sep=" "))
polygon(c(PX[PX>=q[2]], max(PX), q[2]),c(DNR[PX>=q[2],7], 0, 0), col=colors[3], border=colors[3])
polygon(c(q[1], min(PX), PX[PX<=q[1]]),c(0, 0, DNR[PX<=q[1],7]), col=colors[1], border=colors[1])
N<-100*c(round(NCDF[min(which(PX>=q[1])),7],2),1-round(NCDF[min(which(PX>=q[2])),7],2))
legend("bottom", horiz = T, inset = -0.4, title="Probability of being", fill=colors[-2], bty = "n",
       legend=c(as.expression(bquote(paste("below ",.(q[1]) == .(N[1]), " %"))), 
                bquote(paste("above ",.(q[2]) == .(N[2]), " %"))))

#####################   WILLIAM ARRATA - ESSEC PORTFOLIO MANAGEMENT COURSE WINTER 2023   ################

require("pacman")
pacman::p_load("tseries","readxl")

#####################   DATA DOWNLOAD AND COMPUTATION OF EXPECTED RETURNS AND COVARIANCES   ################

#I load the data
data<-as.data.frame(read_excel("stock_prices.xlsx",1))          #load stock prices
data<-apply(data,2,as.numeric)                                  #conversion in numeric
returns<-apply(data[,-1],2,diff)/data[-1,-1]                    #daily historical returns
mean<-252*matrix(colMeans(returns))                             #annualized expected returns
sig<-252*cov(returns)                                           #annualized covariances


################################# SIGN CONSTRAINED EFFICIENT FRONTIER   #####################################

EF = function (returns, nports, shorts, wmax){
  max_ret<-max(mean)
  #max_ret<-(1+as.numeric(shorts)*0.5)*max(mean)     #la cible de renta maximale
  target<-seq(-max_ret, max_ret, len= nports)       #on d�finit les cibles de renta via nports et maxret
  reslow<-rep(-as.numeric(shorts), length(mean))    #vecteur de poids minimum
  reshigh<-rep(wmax,length(mean))                   #vecteur de poids max
  output<-list()
  for (i in seq_along(target)){
    sol<-NULL
    try(sol<-portfolio.optim(returns,pm=target[i]/252,reshigh=reshigh,reslow=reslow, shorts=shorts), silent=T)
    if(!is.null(sol)){
      output[[i]]<-c(i,sqrt(252)*sol$ps,252*sol$pm,sol$pw)
      names(output[[i]])<-c("i","vol","return",paste0("w",1:length(mean)))}
  }
  output<-as.data.frame(do.call(rbind,output))
  rownames(output)<-output$i
  return(output)
}

nports<-300   #nb of ptf, thus we have 300 target expected returns

#Efficient frontier when short selling is forbidden
shorts<-F
wmax<-1       #max weight on each asset class

ptfs_no_s<-EF(returns=returns,nports=nports,shorts=shorts,wmax=wmax)     #some returns not attainable with sign constrained optim
low_no_s<-which.min(ptfs_no_s$vol)
high_no_s<-which.max(ptfs_no_s$return)
effi_no_s<-ptfs_no_s[low_no_s:high_no_s,]


#######################################   RESAMPLING HISTORICAL RETURNS   #####################################


#Simulating n_samp samples of length 250 for the 6 assets classes

require(MASS)
set.seed(33)
n_samp<-1000                                             #number of samples
n_tirages<-250                                           #length of each sample
estim<-resampm<-list()
for (i in 1:n_samp){
  estim[[i]]<-mvrnorm(n_tirages,mean,sqrt(sig))/252}      #daily simulated returns in simu i

#graph of the distribution of daily returns 3 simulations for a given asset
alea<-sort(sample.int(n_samp,3))
dens_ex<-10000*data.frame(estim[[alea[1]]][,6],
                          estim[[alea[2]]][,6],
                          estim[[alea[3]]][,6])/n_samp
dens<-apply(dens_ex, 2, density)

par(mar=c(7,5,4,3),xpd=T)
plot(NA, xlim=range(sapply(dens, "[", "x")), ylim=range(sapply(dens, "[", "y")),xlab="in %",
     ylab="frequency of observation (in %)",main="A few resampled distributions of Herm�s daily stock returns")
mapply(lines, dens, col=1:length(dens))
legend("bottom", horiz=T,inset = c(0,-0.3),text.col=1:length(dens),pch=c(NA,NA),lty=rep(1,3),
       col=1:length(dens), bty="n",legend= paste("simulation",alea))

#graph of the distribution of mean returns across all simu for a given asset class
dens_moy<-density(100*do.call(rbind,resampm)[,6])
dens_moy$y<-100*dens_moy$y/n_samp

plot(NA, xlim=range(dens_moy$x),ylim=range(dens_moy$y),xlab="in %", ylab="frequency of observation (in %)",
     col="darkblue",main="Distribution of expected returns of Herm�s daily stock returns")
lines(dens_moy)

#######################################   RESAMPLED EFFICIENT FRONTIER   #####################################

#I write a new function which has resampled series of returns as input
EF2 = function (nports, shorts, wmax){
  return(EF(returns=estim[[i]], nports, shorts, wmax))}

#I run the optimization for the 1000 simulated sets of returns
resampw<-list()
for (i in 1:n_samp){
  output<-EF2(nports=nports, shorts=shorts, wmax=wmax)
  if (nrow(output)==0){                                #weights are all equal to 0 when no solution
    output<-matrix(c(0,rep(NA,2),rep(0,ncol(returns))),nports,3+ncol(returns),byrow=T,
                   dimnames=list((1:nports),c("i","vol","return",paste0("w",1:ncol(returns)))))}
  else {
    output<-rbind(matrix(c(0,rep(NA,2),rep(0,ncol(returns))),nports-nrow(output),ncol(output),byrow=T,
                         dimnames=list((1:nports)[-output$i],colnames(output))), output)}
  output<-output[order(as.numeric(rownames(output))),]
  resampw[[i]]<-output[,grep("w",colnames(output))]
}

#I average weights, absent solutions also counted and corrected afterward
aveweight<-as.matrix(Reduce("+", resampw)/n_samp)

#rescaling for the number of simulations where the target return is reached and weights are non nil
aveweight<-aveweight/replicate(ncol(aveweight),rowSums(aveweight))

#I apply average weights to initial parameters to get robust efficient frontier
resamp<-as.data.frame(cbind(diag(sqrt(aveweight%*%sig%*%t(aveweight))),aveweight%*%mean))
colnames(resamp)<-c("vol","return")

#graph of the resampled efficient frontiers
col<-c("darkblue","indianred")
par(mar=c(7, 6, 4, 4),xpd=T)
plot(100*ptfs_no_s$vol,100*ptfs_no_s$return,col="darkblue", lwd=2,xlab="standard deviation (%)",
     ylab="expected return (%)",las=1, type="l",pch=20,
     ylim=100*range(c(resamp$return,ptfs_no_s$return)), xlim=100*range(c(resamp$vol,ptfs_no_s$vol)))
lines(100*resamp$vol,100*resamp$return,col="indianred", lwd=2)
legend("bottom", horiz=T,inset = c(0,-0.4),text.col=col,pch=rep(NA,3),lty=rep(1,3),col=col, bty="n",
       legend= c("Markowitz efficient frontier","resampled efficient frontier"))

#weights across the frontier
cum_ave_w<-apply(aveweight,1,cumsum)

#Graph
at_2=seq(1,ncol(cum_ave_w), length.out=7)
colvector<-rainbow(6)
par(mar=c(8,4,4,4) + 0.1,xpd=T)
cex<-0.8
par(cex.axis=cex)
for (i in 1:nrow(cum_ave_w)){
  plot(1:ncol(cum_ave_w),cum_ave_w[1+nrow(cum_ave_w)-i,], xlab="",ylab="", ylim=c(0,1),
       xlim=c(0,ncol(cum_ave_w)),las=1, col=colvector[i],pch=20, axes=F)
  polygon(c(1:ncol(cum_ave_w),ncol(cum_ave_w):1), c(rep(0,ncol(cum_ave_w)),rev(cum_ave_w[1+nrow(cum_ave_w)-i,])),
          col=colvector[i])
  par(new=T)}
axis(1, at=at_2, labels=round(100*resamp$return,1)[at_2], cex.axis =cex)
axis(2, at=seq(0,1,0.25),labels=seq(0,100,25),cex.axis=cex)
mapply(title, c("expected return (%)", "weights (%)"),adj=c(1,0),line=c(-21,0.6))
legend("bottom",ncol=3,inset = c(0,-0.35),legend=rev(colnames(returns)),text.col=colvector,col=colvector,
       lty=1, bty="n")
box()
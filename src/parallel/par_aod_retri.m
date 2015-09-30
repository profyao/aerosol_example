function [sample,error_flag] = par_aod_retri(Date,Path,Orbit,Block,Method,kf,dy,par,core,const,add_limit,delta)
    
    [reg,smart] = load_cache(Date,Path,Orbit,Block,const,'reg','smart');
    
    if sum(reg.reg_is_used(:))==0
        error_flag = 1;
        sample = [];
        fprintf('no region is used!\n')
        return
    else
        error_flag = 0;
    end
    
    Orbit = num2str(Orbit,'%06d');
    Path = num2str(Path,'%03d');
    
    dir_aerosol = fullfile('products/MIL2ASAE/',Date);
    file_aerosol = strcat(dir_aerosol,'/',const.header_MIL2ASAE_filename,Path,'_O',Orbit,'_F12_0022.hdf');

    tau0 = hdfread(file_aerosol, 'RegParamsAlgDiagnostics', 'Fields', 'RegMeanSpectralOptDepth', ...
        'Index',{[Block  1  1  const.Band_Green],[1  1  1  1],[1  const.XDim_r17600  const.YDim_r17600  1]});
    tau0(tau0==-9999) =  mean(tau0(tau0~=-9999));
    tau0 = double(tau0);
    
    ExtCroSect = hdfread(file_aerosol, '/Component Particle Information/Data Table', 'Fields', ...
        'Spectral extinction cross section', 'FirstRecord',1 ,'NumRecords', const.Model_ComponentDim);
    ExtCroSect = ExtCroSect{1}; % RH and band dependent
    CompSSA = hdfread(file_aerosol, '/Component Particle Information/Data Table', 'Fields', ...
        'Spectral single scattering albedo', 'FirstRecord',1 ,'NumRecords', const.Model_ComponentDim);
    CompSSA = CompSSA{1};
            
    [x,y] = find(reg.reg_is_used);
    
    Q = igmrfprec([const.XDim_r, const.YDim_r], 1); % precision matrix for Gaussian Markov Random Field on a given grid
    [i2d, j2d] = find(Q); % find nonzero element indices: 1-D from 1 to 4096 for i and j. size(i)=20160
    mask = (i2d ~= j2d) & reg.reg_is_used(i2d)==true & reg.reg_is_used(j2d)==true;
    i = reg.ind_used(i2d(mask));
    j = reg.ind_used(j2d(mask));
    
    % Dynamically determine component
    if dy == true
    %    [const.Component_Particle,const.Component_Num] = find_mostlik_component(reg,smart,x,y,ExtCroSect,CompSSA,kf,const,false);
    end
    
    if strcmp(Method,'CD')
        iter = 5;
    elseif strcmp(Method,'MCMC')
        iter = 20;
    else
        iter = 20;
    end
    %tau0_r = kron(tau0, ones(RegScale));
	%current.tau = diag(tau0_r(x,y));
    current.tau = nanmean(tau0(:))*ones(reg.num_reg_used,1);
    
    %delta = 0.05;

    if strcmp(Method,'MCMC')
        current.alpha = ones(const.Component_Num,1);                 
        for jj = 1:reg.num_reg_used
            z = gamrnd(current.alpha, 1);
            current.theta(:, jj) = z/sum(z);
        end      
    else
        current.alpha = ones(const.Component_Num,1); % only useful in MCMC 
        current.theta = 1/const.Component_Num * ones(const.Component_Num,reg.num_reg_used);
    end
    
    [current.atm_path,current.surf,current.resid] = par_update_resid(current.tau,current.theta, x, y, smart, reg, ExtCroSect, CompSSA, kf, par,core,add_limit, const);    
    current.sigmasq = update_sigmasq(current.resid,Method);
       
    % Initialize kappa
    if strcmp(Method,'CD-random-noprior')
        current.kappa = 0;
    else
        current.kappa = update_kappa(current.tau,i,j,reg.num_reg_used,Method);
    end
    
    if strcmp(Method,'MCMC')
           
        sample.tau = zeros(reg.num_reg_used, iter+1);
        sample.tau(:,1) = current.tau;
        sample.alpha = zeros(const.Component_Num, iter+1);
        sample.alpha(:,1) = current.alpha;
        sample.theta = zeros(const.Component_Num, reg.num_reg_used, iter+1);
        sample.theta(:,:,1) = current.theta;

        sample.atm_path = zeros(const.NChannel,reg.num_reg_used,iter+1);
        sample.surf = zeros(const.NChannel,reg.num_reg_used,iter+1);
        sample.resid = zeros(const.NChannel,reg.num_reg_used,iter+1);

        sample.atm_path(:,:,1) = current.atm_path;
        sample.surf(:,:,1) = current.surf;
        sample.resid(:,:,1) = current.resid;

        sample.sigmasq = zeros(const.NChannel, iter+1);
        sample.sigmasq(:,1) = current.sigmasq;

        sample.kappa = zeros(iter+1,1);
        sample.kappa(1) = current.kappa;
        
    end
    
    %sample.loglik = zeros(iter+1,1);
    %[sample.loglik(1),num] = log_lik(current,i,j,const.Channel_Used,Method);
    
    %fprintf('Round: %d, Log-lik: %.4e, active: %d \n',0,sample.loglik(1),num);
    
    %if strcmp(Method,'MISR')
        
    %    CompModNum = hdfread(file_aerosol, '/Mixture Information/Mixture Data', 'Fields', ...
    %'Component model number', 'FirstRecord', 1,'NumRecords', const.Model.MixtureDim);
    %    MixSSA = hdfread(file_aerosol, '/Mixture Information/Mixture Data', 'Fields', ...
    %'Mixture spectral single scattering albedo', 'FirstRecord', 1 ,'NumRecords', const.Model.MixtureDim);
    %    CompFrac = hdfread(file_aerosol, '/Mixture Information/Component Fractional Spectral Optical Depth', ...
    %'Index', {[1  1  1],[1  1  1],[const.Band.Dim   const.Model.NumComponent  const.Model.MixtureDim]});
        
    %    sample = par_aod_retr_search(x,y,reg,smart,CompModNum,MixSSA,CompFrac,ExtCroSect,const,add_limit);
        
    %else
    
    [current.loglik,num] = log_lik(current,i,j,const.Channel_Used,Method);
    fprintf('Round: 0, Log-lik: %.4e, active: %d \n',current.loglik,num);

    for t = 1: iter
        %clf
        %show(sample,reg,2,1,t,jet(256),const)   
        %M=getframe;

        [current.tau,current.resid] = par_update_tau(current.tau,current.theta,current.resid,current.kappa,current.sigmasq,...
            delta,i, j, x, y, smart, reg, ExtCroSect, CompSSA, Method, kf, par, core, add_limit, const);

        if strcmp(Method,'CD-random-noprior')
            current.kappa = 0;
        else
            current.kappa = update_kappa(current.tau,i,j,reg.num_reg_used,Method);
        end

        [current.theta, current.resid] = par_update_theta(current.theta,current.tau,current.resid,current.sigmasq,current.alpha,...
            i, j, x, y, smart, reg, ExtCroSect, CompSSA, Method, kf, par, core, add_limit, const);

        if strcmp(Method,'MCMC')
            current.alpha = sample_alpha(current.alpha,current.theta',const.Component_Num,reg.num_reg_used);
            sample.alpha(:,t+1) = current.alpha;
        end

        current.sigmasq = update_sigmasq(current.resid,Method);

        [current.atm_path,current.surf,~] = par_update_resid(current.tau,current.theta, x, y, smart, reg, ExtCroSect, CompSSA, kf, par,core,add_limit, const);
        
        if strcmp(Method,'MCMC')
            sample.tau(:,t+1) = current.tau;
            sample.kappa(t+1) = current.kappa;
            sample.theta(:,:,t+1) = current.theta;
            sample.sigmasq(:,t+1) = current.sigmasq;
            sample.resid(:,:,t+1) = current.resid;
            sample.atm_path(:,:,t+1) = current.atm_path;
            sample.surf(:,:,t+1) = current.surf;
        end
        
        %[sample.loglik(t+1),num] = log_lik(current,i,j,const.Channel_Used,Method);
        %fprintf('Round: %d, Log-lik: %.4e, active: %d \n',t,sample.loglik(t+1),num);
        fprintf('.');

    end    
    %end
    
    [current.loglik,num] = log_lik(current,i,j,const.Channel_Used,Method);
    fprintf('\nRound: %d, Log-lik: %.4e, active: %d \n',t,current.loglik,num);
    
    if ~strcmp(Method,'MCMC')
        sample = current;
    end

end
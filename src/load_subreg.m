function subreg = load_subreg(Date,Path,Orbit,Block,const)
    
    Orbit = num2str(Orbit,'%06d');
    Path = num2str(Path,'%03d');

    % Load MI1B2T data, make averages and conversions
    subreg = NaN *ones(const.XDim_r1100, const.YDim_r1100, const.Band_Dim, const.Cam_Dim);
    dir_radiance = fullfile('products/MI1B2T/',Date);

    for cam = 1:const.Cam_Dim
        
        file_rad = strcat(dir_radiance,'/',const.header_MI1B2T_filename,Path,'_O',Orbit,'_',const.Cam_Name{cam},'_F03_0024.hdf');
        disp(['Loading', file_rad, '...']);

        for band = 1:const.Band_Dim
            disp(['Loading band', const.Band_Name{band}, '...']);
            block_resolution = hdfread(file_rad, ['/', const.Band_Name{band}, '/Grid Attributes/Block_size.resolution_x'], 'Fields', 'AttrValues', 'FirstRecord',1 ,'NumRecords',1);
            block_size_x = hdfread(file_rad, ['/', const.Band_Name{band}, '/Grid Attributes/Block_size.size_x'], 'Fields', 'AttrValues', 'FirstRecord',1 ,'NumRecords',1);
            block_size_y = hdfread(file_rad, ['/', const.Band_Name{band}, '/Grid Attributes/Block_size.size_y'], 'Fields', 'AttrValues', 'FirstRecord',1 ,'NumRecords',1);
            scale_factor = hdfread(file_rad, ['/', const.Band_Name{band}, '/Grid Attributes/Scale factor'], 'Fields', 'AttrValues', 'FirstRecord',1 ,'NumRecords',1);
            sun_distance_au = hdfread(file_rad, ['/', const.Band_Name{band}, '/Grid Attributes/SunDistanceAU'], 'Fields', 'AttrValues', 'FirstRecord',1 ,'NumRecords',1);
            std_solar_wgted_height = hdfread(file_rad, ['/', const.Band_Name{band}, '/Grid Attributes/std_solar_wgted_height'], 'Fields', 'AttrValues', 'FirstRecord',1 ,'NumRecords',1);

            radiance_rdqi = hdfread(file_rad, const.Band_Name{band}, 'Fields', const.Band_Radiance{band}, ...
                'Index', {[Block  1  1], [1  1  1], [1  double(block_size_x{1})  double(block_size_y{1})]});

            rdqi = bitand(radiance_rdqi,3);
            radiance = double(bitshift(radiance_rdqi,-2));
            radiance(radiance >= 16377) = NaN;
            radiance = double(radiance)*scale_factor{1};

            if  double(block_resolution{1}) == const.r275
                disp('Averaging radiances to 1.1-km resolution ...')
                radiance_ave = NaN * ones(const.XDim_r1100, const.YDim_r1100);
                radiance(rdqi > const.Config_rdqi1) = NaN;
                for kk = 1:const.XDim_r1100
                    for ll = 1:const.YDim_r1100
                        r = radiance(4*kk-3:4*kk, 4*ll-3:4*ll);
                        if any(r(:))
                            radiance_ave(kk,ll) = nanmean(r(:));
                        end
                    end
                end
                radiance = radiance_ave;
            else
                fprintf('already 1.1-km resolution, no need to average...\n')
            end

            subreg(:,:,band,cam) = pi*radiance*sun_distance_au{1}^2/std_solar_wgted_height{1};
        end
    end

    dir_aerosol = fullfile('products/MIL2ASAE/',Date);
    file_aerosol = strcat(dir_aerosol,'/',const.header_MIL2ASAE_filename,Path,'_O',Orbit,'_F12_0022.hdf');

    % Apply spectral out-of-band correction
    disp('apply spectral out-of-band correction')
    for ii = 1:const.XDim_r1100
        for jj = 1:const.YDim_r1100
            for cam = 1:const.Cam_Dim
                rho = squeeze(subreg(ii, jj, :, cam));
                if all(~isnan(rho))
                    subreg(ii,jj,:,cam) = const.Config_spectral_corr_matrix*rho;
                end
            end
        end
    end

    % Correct for ozone absorption
    disp('correct for ozone absorption')
    ColOzAbund = hdfread(file_aerosol, 'RegParamsEnvironmental', 'Fields', 'ColOzAbund', ...
        'Index',{[Block  1  1],[1  1  1],[1  const.XDim_r17600  const.YDim_r17600]});
    SolZenAng = hdfread(file_aerosol, 'RegParamsGeometry', 'Fields', 'SolZenAng', ...
        'Index',{[Block  1  1],[1  1  1],[1  const.XDim_r17600  const.YDim_r17600]});
    ViewZenAng = hdfread(file_aerosol, 'RegParamsGeometry', 'Fields', 'ViewZenAng', ...
        'Index',{[Block  1  1  1],[1  1  1  1],[1  const.XDim_r17600  const.YDim_r17600  const.Cam_Dim]});
    for band = 1:const.Band_Dim
        for cam = 1:const.Cam_Dim
            c = exp(const.Config_c_lambda(band)*ColOzAbund.*(1./cosd(SolZenAng)+1./cosd(ViewZenAng(:,:,cam))));
            subreg(:, :, band, cam) = subreg(:, :, band, cam) .* kron(c, ones(const.RegSize*const.RegScale));
        end
    end
    
    % Subregions screening
    disp('subregion screening')
    RetrAppMask = hdfread(file_aerosol, 'SubregParamsAer', 'Fields', 'RetrAppMask', ...
        'Index',{[Block  1  1  1  1],[1  1  1  1  1],[1  const.XDim_r1100  const.YDim_r1100  const.Band_Dim  const.Cam_Dim]});
    subreg(RetrAppMask ~= 0) = NaN;
    
end
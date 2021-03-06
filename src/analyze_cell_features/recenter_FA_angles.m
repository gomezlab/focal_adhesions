function recenter_FA_angles(exp_dir,varargin)

tic;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%Setup variables and parse command line
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
i_p = inputParser;

i_p.addRequired('exp_dir',@(x)exist(x,'dir') == 7);

i_p.addParamValue('debug',0,@(x)x == 1 || x == 0);
i_p.addOptional('by_hand_direction',NaN,@(x)isnumeric(x) && abs(x) <= 180 && abs(x) >= 0);

i_p.parse(exp_dir,varargin{:});

%Add the folder with all the scripts used in this master program
addpath(genpath('../find_cell_features'));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%Main Program
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

FA_angles = csvread(fullfile(exp_dir,'adhesion_props','lin_time_series','Angle_to_FA_cent.csv'));
FA_cent_pos = csvread(fullfile(exp_dir,'adhesion_props','single_props','Adhesion_centroid.csv'));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Find Centroid Direction
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

cent_pos_diffs = zeros((size(FA_cent_pos,1)-1),2);
for i=2:size(FA_cent_pos,1)
    cent_pos_diffs(i-1,1) = (FA_cent_pos(i,1) - FA_cent_pos(i-1,1));
    cent_pos_diffs(i-1,2) = (FA_cent_pos(i,2) - FA_cent_pos(i-1,2))*-1;
end

sum_cent_movement = sum(cent_pos_diffs);
mean_cent_movement = mean(cent_pos_diffs);

cent_direction = atan2(sum_cent_movement(2),sum_cent_movement(1))*(180/pi);

%if the cell direction is specified in the parameter set, we will use that
%for the recentering
if (not(isnan(i_p.Results.by_hand_direction)))
    cent_direction = i_p.Results.by_hand_direction;
end

csvwrite(fullfile(exp_dir,'adhesion_props','cell_direction.csv'), ...
    [i_p.Results.by_hand_direction,cent_direction]);
csvwrite(fullfile(exp_dir,'adhesion_props','movement_magnitude.csv'), ...
    sqrt(mean_cent_movement(1)^2+mean_cent_movement(2)^2));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Recenter and Save Results
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

FA_angles = FA_angles - cent_direction;

FA_angles(FA_angles < -180) = FA_angles(FA_angles < -180) + 360;
FA_angles(FA_angles > 180) = FA_angles(FA_angles > 180) - 360;

csvwrite(fullfile(exp_dir,'adhesion_props','lin_time_series','FA_angle_recentered.csv'),FA_angles);

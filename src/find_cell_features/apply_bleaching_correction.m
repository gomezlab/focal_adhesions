function apply_bleaching_correction(exp_dir,varargin)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Setup variables and parse command line
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
tic;

i_p = inputParser;

i_p.addRequired('exp_dir',@(x)exist(x,'dir') == 7);
i_p.addOptional('debug',0,@(x)x == 1 | x == 0);
i_p.parse(exp_dir,varargin{:});

%Add the folder with all the scripts used in this master program
addpath(genpath('matlab_scripts'));

filenames = add_filenames_to_struct(struct());

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Main Program
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Determine single image folders
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
image_dir = fullfile(exp_dir, 'individual_pictures');

single_image_folders = dir(image_dir);

assert(strcmp(single_image_folders(1).name, '.'), 'Error: expected "." to be first string in the dir command')
assert(strcmp(single_image_folders(2).name, '..'), 'Error: expected ".." to be second string in the dir command')
assert(str2num(single_image_folders(3).name) == 1, 'Error: expected the third string to be image set one') %#ok<ST2NM>

single_image_folders = single_image_folders(3:end);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Collect the intensity correction
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

expression_levels = zeros(1,length(single_image_folders));
after_correction = zeros(1,length(single_image_folders));
sum_expression_levels = zeros(1,length(single_image_folders));
for i=1:length(single_image_folders)
    base_image_file = fullfile(image_dir,single_image_folders(i).name,filenames.focal_image);
    uncorrected_image_file = fullfile(image_dir,single_image_folders(i).name,['uncorrected_',filenames.focal_image]);
    if (exist(uncorrected_image_file,'file'))
        disp('Found corrected image file, not applying correction.');
        continue;
    end
    
    image = imread(base_image_file);
    
    expression_levels(i) = mean(image(:));
    sum_expression_levels(i) = sum(image(:));
    
    movefile(base_image_file,uncorrected_image_file);
    
    cor_image = image.*(expression_levels(1)/expression_levels(i));
    after_correction(i) = mean(cor_image(:));
    imwrite(cor_image, base_image_file,'Bitdepth',16);
end

csvwrite(fullfile(exp_dir,'adhesion_props','mean_levels.csv'),expression_levels)
csvwrite(fullfile(exp_dir,'adhesion_props','after_p_correction.csv'),expression_levels)
csvwrite(fullfile(exp_dir,'adhesion_props','integrated_levels.csv'),sum_expression_levels)

toc;

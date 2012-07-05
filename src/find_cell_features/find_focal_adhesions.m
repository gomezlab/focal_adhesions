function [varargout] = find_focal_adhesions(I_file,varargin)
% FIND_FOCAL_ADHESIONS    locates the focal adhesions in a given image,
%                         optionally returns the segmented image or writes
%                         the segmented image to a file
%
%   find_focal_adhesions(I,OPTIONS) locate the focal adhesions in image
%   file, 'I'
%
%   Options:
%
%       -cell_mask: file which contains the cell mask
%       -filter_size: size of the averaging filter to use, defaults to 23
%       -output_dir: folder used to hold all the results, defaults to the
%        same folder as the image file, 'I'
%       -debug: set to 1 to output debugging information, defaults to 0

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Setup variables and parse command line
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
tic;
i_p = inputParser;
i_p.StructExpand = true;
i_p.addRequired('I_file',@(x)exist(x,'file') == 2);

i_p.parse(I_file);

%Adhesion filtering parameters
i_p.addParamValue('min_adhesion_size',1,@(x)isnumeric(x) && x > 0);
i_p.addParamValue('filter_size',11,@(x)isnumeric(x) && x > 1);
i_p.addParamValue('min_independent_size',14,@(x)isnumeric(x) && x > 0);

i_p.addParamValue('min_seed_size',NaN,@(x)isnumeric(x) && x > 0);

i_p.addParamValue('no_ad_splitting', 0, @(x) islogical(x) || x == 1 || x == 0);

i_p.addParamValue('max_adhesion_count', Inf, @(x) isnumeric(x));
i_p.addParamValue('stdev_thresh',2,@(x)isnumeric(x) && all(x > 0));
i_p.addParamValue('per_image_thresh',0,@(x)islogical(x) || x == 0 || x == 1);

i_p.addParamValue('proximity_filter',0,@(x)isnumeric(x) && all(x >= 0));

i_p.addParamValue('debug',0,@(x)x == 1 || x == 0);
i_p.addParamValue('paper_figures',0,@(x)x == 1 || x == 0);
i_p.addParamValue('status_messages',1,@(x)x == 1 || x == 0);

i_p.parse(I_file,varargin{:});

%Add the folder with all the scripts used in this master program
addpath('matlab_scripts');
addpath('../visualize_cell_features');

filenames = add_filenames_to_struct(struct());

%read in the cell mask image if defined in parameter set
if (exist(fullfile(fileparts(I_file),filenames.cell_mask),'file'))
    cell_mask = imread(fullfile(fileparts(I_file),filenames.cell_mask));
end

%read in and normalize the input focal adhesion image
focal_image  = double(imread(I_file));
if (exist(fullfile(fileparts(I_file),filenames.focal_image_min_max),'file'))
    image_set_min_max = csvread(fullfile(fileparts(I_file),filenames.focal_image_min_max));
else
    image_set_min_max = quantile(focal_image(:),[0.001,0.999]);
end

focal_normed = (focal_image - image_set_min_max(1))/(range(image_set_min_max));

output_dir = fileparts(I_file);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Main Program
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Apply filters to find adhesion regions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
I_filt = fspecial('disk',i_p.Results.filter_size);
blurred_image = imfilter(focal_image,I_filt,'same',mean(focal_image(:)));
high_passed_image = focal_image - blurred_image;

filter_file = fullfile(fileparts(I_file),filenames.focal_image_threshold);

if (i_p.Results.per_image_thresh || not(exist(filter_file,'file')))
    filter_thresh = mean(high_passed_image(:)) + std(high_passed_image(:))*i_p.Results.stdev_thresh;
else
    overall_filter_vals = csvread(filter_file);
    filter_thresh = overall_filter_vals(1) + overall_filter_vals(2)*i_p.Results.stdev_thresh;
end

threshed_image = find_threshed_image(high_passed_image,filter_thresh, ...
    i_p.Results.proximity_filter,i_p.Results.min_seed_size);

%identify and remove adhesions on the edge of the image
threshed_image = remove_edge_adhesions(threshed_image);

%filter out small adhesions if requested
if (i_p.Results.min_adhesion_size > 1)
    labeled_thresh = bwlabel(threshed_image,4);
    
    props = regionprops(labeled_thresh,'Area'); %#ok<MRPBW>
    labeled_thresh = ismember(labeled_thresh, find([props.Area] >= i_p.Results.min_adhesion_size));
    
    threshed_image = labeled_thresh > 0;
end

% Remove adhesions outside mask
if (exist('cell_mask','var'))
    temp_label = bwlabel(threshed_image,4);
    inside_mask = temp_label .* cell_mask;
    inside_mask_ad_nums = unique(inside_mask(:));
    inside_mask_ad_nums = inside_mask_ad_nums(2:end);
    
    threshed_image = ismember(temp_label,inside_mask_ad_nums);
end

%adding a check for finding adhesions, if didn't find any, output error
%file and die
if (sum(sum(threshed_image)) == 0)
    no_ad_found_file = fullfile(output_dir, 'no_ads_found.txt');
    system(['touch ', no_ad_found_file]);
    warning('FA:noadsfound','Didn''t find any adhesions');
    return;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Adhesion Segmentation
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

seg_start = tic;
%If adhesion splitting is off ('no_ad_splitting'), then watershed based
%segmentation isn't needed because all the watershed method adds is the
%ability to split touching adhesions. Also, we need to know the pixel size
%in order to select a threshold for having adhesions remain as seperate
%enties when touching, so we also check for that before using the watershed
%segmentation
if (i_p.Results.no_ad_splitting || any(strcmp('min_independent_size',i_p.UsingDefaults)))
    %if splitting is off, there is no need to use the fancy watershed based
    %segmentation methods, just identify the connected areas
    ad_segment = bwlabel(threshed_image,4);
else
    
    ad_segment = watershed_min_size(high_passed_image,bwlabel(threshed_image,4), ...
        i_p.Results.min_independent_size);
end
toc(seg_start);
if(i_p.Results.status_messages), disp('Done finding adhesion regions'); end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Check for too many adhesions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
ad_nums = unique(ad_segment)';
assert(ad_nums(1) == 0, 'Background pixels not found after building adhesion label matrix')
if ((length(ad_nums) - 1) > i_p.Results.max_adhesion_count)
    highlighted_image = create_highlighted_image(focal_normed, im2bw(ad_segment,0), ...
        'color_map',[1,1,0]);
    imwrite(highlighted_image,fullfile(output_dir, 'highlights.png'));
    system(['touch ', fullfile(output_dir, 'Found_too_many_adhesions')]);
    error(['Found more (',num2str(max(ad_segment(:))),') adhesions than', ...
        ' max adhesion count (',num2str(i_p.Results.max_adhesion_count),').']);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Find and fill holes in single adhesions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
holes_start = tic;
filled_ads = imfill(ad_segment,'holes');
hole_pixels = unique(filled_ads(filled_ads & not(ad_segment)));

for this_num = hole_pixels'
    %first make a binary image of the current adhesion and then run imfill
    %to fill any holes present
    this_ad = zeros(size(ad_segment));
    this_ad(ad_segment == this_num) = 1;
    filled_ad = imfill(this_ad,'holes');
    
    ad_segment(logical(filled_ad)) = this_num;
    if (i_p.Results.debug && mod(this_num,50)==0)
        disp(['Done filling holes in ',num2str(this_num), '/', num2str(length(ad_nums))]);
    end
end
toc(holes_start);
if(i_p.Results.status_messages), disp('Done filling adhesion holes'); end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Renumber adhesions to be sequential
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
ad_nums = unique(ad_segment);
assert(ad_nums(1) == 0, 'Background pixels not found after building adhesion label matrix')
for i = 2:length(ad_nums)
    ad_segment(ad_segment == ad_nums(i)) = i - 1;
end
if(i_p.Results.status_messages), disp('Done renumbering adhesion regions'); end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Build adhesion perimeters image
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
ad_segment_perim = zeros(size(ad_segment));
for i = 1:max(ad_segment(:))
    assert(any(any(ad_segment == i)), 'Error: can''t find ad number %d', i);
    this_ad = zeros(size(ad_segment));
    this_ad(ad_segment == i) = 1;
    ad_segment_perim(bwperim(this_ad)) = i;
end
if(i_p.Results.status_messages), disp('Done building adhesion perimeters'); end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Write the output files
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

imwrite(double(ad_segment)/2^16,fullfile(output_dir, filenames.adhesions),'bitdepth',16);
imwrite(double(ad_segment_perim)/2^16,fullfile(output_dir, filenames.adhesions_perim),'bitdepth',16);
imwrite(im2bw(ad_segment,0),fullfile(output_dir, filenames.adhesions_binary));

highlighted_image = create_highlighted_image(focal_normed, im2bw(ad_segment_perim,0), 'color_map',[1,1,0]);
if (exist('cell_mask','var'))
    highlighted_image = create_highlighted_image(highlighted_image, bwperim(cell_mask),'color_map',[1,0,0]);
end
imwrite(highlighted_image,fullfile(output_dir, 'highlights.png'));

%Color Highlights
% c_map = jet(max(ad_segment_perim(:)));
% c_map = c_map(randsample(size(c_map,1),size(c_map,1)),:);
% highlighted_image = create_highlighted_image(focal_normed, ad_segment_perim,'color_map',c_map);
% imwrite(highlighted_image,fullfile(output_dir, 'color_highlights.png'));

if (i_p.Results.paper_figures)
    col_range = (find(sum(ad_segment),1,'first')-5):(find(sum(ad_segment),1,'last')+5);
    col_range = col_range(col_range > 0 & col_range < size(ad_segment,2));
    row_range = (find(sum(ad_segment,2),1,'first')-5):(find(sum(ad_segment,2),1,'last')+5);
    row_range = row_range(row_range > 0 & row_range < size(ad_segment,1));
    
    normed_hp_image = (high_passed_image - min(high_passed_image(:)))/range(high_passed_image(:));
    normed_hp_image = normed_hp_image(row_range,col_range);
    imwrite(normed_hp_image,fullfile(output_dir,'high_passed_image.png'),'bitdepth',16);
    
    imwrite(highlighted_image(row_range,col_range,1:3),fullfile(output_dir,'highlights_cropped.png'));
    imwrite(focal_normed(row_range,col_range),fullfile(output_dir,'focal_cropped.png'));
end

%diagnostic diagram
% hist(high_passed_image(:),100);
% xlabel('High Pass Filtered Intensity','FontSize',16,'FontName','Helvetica');
% ylabel('Pixel Count','FontSize',16,'FontName','Helvetica');
% y_limits = ylim();
% 
% set(gca, 'FontName','Helvetica','FontSize',16,'Box','off');
% set(gcf, 'PaperPositionMode', 'auto');
% print('-dpng', fullfile(output_dir,'high_passed_intensities.png'));
% close;

if (nargout > 0)
    varargout{1} = struct('adhesions',im2bw(ad_segment,0),'ad_segment',ad_segment);
end
toc;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function threshed_image = find_threshed_image(high_passed_image, filter_thresh, ...
    proximity_filter,min_seed_size)

if (length(filter_thresh) == 1)
    threshed_image = high_passed_image >= filter_thresh;
else
    high_threshed_image = high_passed_image >= filter_thresh(2);
    
    if (not(isnan(min_seed_size)))
        high_threshed_labels = bwlabel(high_threshed_image);
        high_threshed_props = regionprops(high_threshed_labels,'Area');
        
        high_threshed_image = ismember(high_threshed_labels,find([high_threshed_props.Area] >= 4));
    end
    
    high_threshed_image = imdilate(high_threshed_image,strel('disk',proximity_filter));
    
    low_threshed_image = high_passed_image >= filter_thresh(1);
    low_thresh_bwlabel = bwlabel(low_threshed_image,4);
    
    overlap_labels = unique(low_thresh_bwlabel.*high_threshed_image);
    if (overlap_labels(1) == 0)
        overlap_labels = overlap_labels(2:end);
    end
    
    threshed_image = ismember(low_thresh_bwlabel,overlap_labels);
end
1;
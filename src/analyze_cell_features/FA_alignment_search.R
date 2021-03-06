###############################################################################
# FA Orientation Models
###############################################################################

gather_FA_orientation_data <- function(exp_dir,fixed_best_angle = NA,
    min.ratio = 3,output.file = 'FA_orientation.Rdata',diagnostic.figure=F,
    output.dir=NA) {
    
    if (is.na(output.dir)) {
        output.dir = file.path(exp_dir,'..');
    }

    data_set = read_in_orientation_data(exp_dir, min.ratio=min.ratio);
    print('Done reading in data set')

    ###########################################################################
    # Overall Angle Search
    ###########################################################################
    data_set$angle_search = test_dom_angles(data_set$high_ratio$orientation);
    print('Done searching potential dominant angles')
    if (is.na(fixed_best_angle)) {
        data_set$best_angle = find_best_alignment_angle(data_set$angle_search)
    } else {
        data_set$best_angle = fixed_best_angle
        data_set$actual_best_angle = find_best_alignment_angle(data_set$angle_search)
    }

    data_set$corrected_orientation = apply_new_orientation(data_set$high_ratio$orientation,
        data_set$best_angle)
    data_set$FAAI = find_FAAI_from_orientation(data_set$corrected_orientation)
    print('Done finding best orientation')

    ###########################################################################
    # Area Bin Angle Search
    ###########################################################################
    for (area_class in names(data_set$area_sets)) {
        this_or = data_set$area_sets[[area_class]]$orientation
        if (length(this_or) == 0) {
            next;
        }

        temp = list()

        temp$angle_search = test_dom_angles(this_or);
        temp$best_angle = find_best_alignment_angle(temp$angle_search)

        temp$corrected_orientation = apply_new_orientation(this_or,
            temp$best_angle)
        
        temp$FAAI = find_FAAI_from_orientation(temp$corrected_orientation);

        data_set$area_results[[area_class]] = temp;
        print(paste('Done with area class:', area_class))
    }

    ###########################################################################
    # Per Image/Adhesion FAAI Search
    ###########################################################################
	temp = find_per_image_dom_angle(data_set$mat, min.ratio=min.ratio)
    data_set$per_image_dom_angle = temp$best_angles
    data_set$per_image_FAAI	 = temp$FAAI
    write.table(t(data_set$per_image_dom_angle),file=file.path(output.dir,'per_image_dom_angle.csv'),
        row.names=F,col.names=F,sep=',')
    write.table(t(data_set$per_image_FAAI),file=file.path(output.dir,'per_image_FAAI.csv'),
        row.names=F,col.names=F,sep=',')
	
	dir.create(file.path(output.dir,'per_image_angles'));
	for (i_num in 1:length(temp$passed_angles)) {
		write.table(temp$passed_angles[[i_num]],
					file=file.path(output.dir,'per_image_angles',sprintf('%s.csv',i_num)),
					row.names=F,col.names=F,sep=',')
	}

    print('Done searching for best angle in single images')
    
    data_set$single_ad_deviances = gather_all_single_adhesion_deviances(data_set);
    print('Done analyzing single adhesions')
    
    save(data_set,file=file.path(output.dir,output.file))
    
    ###########################################################################
    # Diagnostic Figure
    ###########################################################################
    if (! diagnostic.figure) {
        return(data_set);
    }
    pdf(file.path(output.dir,'adhesion_orientation.pdf'))
    layout(rbind(c(1,2),c(3,4),c(5,5)))
    par(bty='n', mar=c(4,4.2,2,0),mgp=c(2,1,0))
    
    hist(data_set$high_ratio$orientation,main='Pos X-axis Reference',
        xlab=paste('Angle n=',dim(data_set$high_ratio)[1],sep=''), breaks=seq(-90,90,by=10));
    
    plot(data_set$angle_search$test_angles,data_set$angle_search$angle_FAAI,typ='l',
        xlab='Dominant Search Angle',ylab='FA Alignment Index',ylim=c(0,90));
    lines(data_set$angle_search$test_angles, abs(data_set$angle_search$mean_angle), col='red')
    lines(data_set$angle_search$test_angles, abs(data_set$angle_search$median_angle), col='blue')
    if (! is.na(fixed_best_angle)) {
        segments(fixed_best_angle,0,fixed_best_angle,2000,col='blue')
        segments(data_set$actual_best_angle,0,data_set$actual_best_angle,2000,col='green')
    } else {
        segments(data_set$best_angle,0,data_set$best_angle,2000,col='green')
    }

    hist(data_set$corrected_orientation,
        main=paste0('Rotated ',data_set$best_angle,'\u00B0 / ',
            sprintf('FAAI=%0.1f',find_FAAI_from_orientation(data_set$corrected_orientation))),
        xlab=paste('Angle n=',dim(data_set$high_ratio)[1],sep=''), breaks=seq(-90,90,by=10));
    
    plot(data_set$per_image_dom_angle,xlab='Image Number',ylab='Dominant Angle',ylim=c(0,180));
    
    print(dim(data_set$single_ad_deviances)[1])
    #deal with the case where there aren't any single adhesion deviances
    #quantified, specified as an empty results set
    if (dim(data_set$single_ad_deviances)[1] != 0) {
        hist(data_set$single_ad_deviances$mean_dev,main='')
    }

    graphics.off()

    return(data_set)
}

read_in_orientation_data <- function(time_series_dir,min.ratio = 3) {
    data_set = list();
 	
    data_set$mat$orientation = read.csv(file.path(time_series_dir,'Orientation.csv'),header=F);
    data_set$mat$area = read.csv(file.path(time_series_dir,'Area.csv'),header=F);
    
    major_axis = read.csv(file.path(time_series_dir,'MajorAxisLength.csv'),header=F);
    minor_axis = read.csv(file.path(time_series_dir,'MinorAxisLength.csv'),header=F);
    data_set$mat$major_axis = major_axis;
    data_set$mat$minor_axis = minor_axis;
    data_set$mat$ratio = major_axis/minor_axis;
	
    unlist_data_set = list()
    for (i in names(data_set$mat)) {
        unlist_data_set[[i]] = unlist(data_set$mat[[i]]);
    }
    unlist_data_set = as.data.frame(unlist_data_set);
    data_set$high_ratio = subset(unlist_data_set, !is.nan(unlist_data_set$ratio) & 
        unlist_data_set$ratio >= min.ratio);
    
    #Area seperations/binning - hard thresholds set based on distributions of
    #NS and 2xKD cells 100ug/ml
    area_thresholds = c(0.53,1.26);

    data_set$area_sets$small = subset(data_set$high_ratio, 
        area <= area_thresholds[1]);
    data_set$area_sets$medium = subset(data_set$high_ratio, 
        area > area_thresholds[1] & area <= area_thresholds[2]);
    data_set$area_sets$large = subset(data_set$high_ratio, 
        area > area_thresholds[2]);

    return(data_set);
}

find_per_image_dom_angle <- function(mat_data, min.ratio=3) {
    best_angles = c()
    passed_angles = list()
    FAAI = c()
    for (i_num in 1:dim(mat_data$orientation)[2]) {
        this_orientation = mat_data$orientation[,i_num];
        this_ratio = mat_data$ratio[,i_num];

        good_rows = !is.na(this_orientation) & this_ratio >= min.ratio;
        
        #deal with the case where there are very few elongated adhesions
        #present in the image, put in place holders and skip to next image
        if (sum(good_rows) < 3) {
            best_angles = c(best_angles, NA);
            passed_angles[[i_num]] = NA;
    		FAAI = c(FAAI, NA);
            next;
        }
        this_orientation = this_orientation[good_rows];

        angle_search = test_dom_angles(this_orientation);
        best_angle = find_best_alignment_angle(angle_search)
		
		best_orientation = apply_new_orientation(this_orientation,best_angle)
		image_FAAI = find_FAAI_from_orientation(best_orientation)
        
		passed_angles[[i_num]] = best_orientation;
        best_angles = c(best_angles, best_angle);
		FAAI = c(FAAI,image_FAAI);
    }
	temp = list(best_angles = best_angles, FAAI=FAAI, passed_angles = passed_angles);	
    return(temp)
}

test_dom_angles <- function(orientation) {
    # We only need to test those dominate angles where there will be a shift in
    # the standard deviation of the data set. Since SD can only change when an
    # angle has flipped through the -90 back to 90 side, we only need to test a
    # single point between each unique angle. This next command pulls out those
    # unique angles and rotates them to the 0 - 180 range
    angle_list = unique(sort(orientation)) + 90;

    # Now we will pick out a point between each of those angles, in particular
    # the mean angle, unless there is only one unique value, in that case, it
    # doesn't matter what angles we test, all will maximimze the FAAI, so skip forward
    angles_to_test = c()
    if (length(angle_list) <= 2) {
        angles_to_test = mean(angle_list);
    } else {
        for (i in 1:(length(angle_list) - 1)) {
            angles_to_test = c(angles_to_test, mean(angle_list[i:(i+1)]));
        }
    }
    angles_to_test = c(0,angles_to_test);
    results = list(x = angles_to_test, test_angles = angles_to_test);
    
    mean_angle = c()
    median_angle = c()
    new_angle_FAAI = c()
    for (angle in angles_to_test) {
        new_orientation = apply_new_orientation(orientation,angle);
        mean_angle = c(mean_angle,mean(new_orientation, na.rm=T));
        median_angle = c(median_angle,median(new_orientation, na.rm=T));
        new_angle_FAAI = c(new_angle_FAAI, find_FAAI_from_orientation(new_orientation));
    }
        
    results$y = new_angle_FAAI;
    results$mean_angle = mean_angle;
    results$median_angle = median_angle;
    results$angle_FAAI = new_angle_FAAI;
    results$FA_angles = orientation;

    return(results)
}

find_FAAI_from_orientation <- function(orientation_data) {
    return(90-sd(orientation_data, na.rm=T));
}

find_best_alignment_angle <- function(test_angle_set) {
    # to select the best angle, find the angle with the maximum FAAI, from
    # those angles select the angle with the lowest absolute value of the mean
    # angle
    max_FAAI_angle = test_angle_set$test_angles[test_angle_set$angle_FAAI == max(test_angle_set$angle_FAAI)];
    
    # deal with a degenerate case where there are multiple max FAAI angles,
    # this typically happens when there is only one angle in the data set. In
    # that case only two angles were tested, 0 and the angle, thus, it doesn't
    # matter what angle we select here, the angle will be corrected below.
    if (length(max_FAAI_angle) > 1) {
        if (max_FAAI_angle[1] != 0) {
            print("You shouldn't hit this message, if you do, time to investigate");
        }
        max_FAAI_angle = max_FAAI_angle[1];
    }
    
    corrected_orientation = apply_new_orientation(test_angle_set$FA_angles,max_FAAI_angle);
    best_angle = max_FAAI_angle + mean(corrected_orientation,na.rm=T);
    best_angle = round(best_angle,2);
    return(best_angle);
}

apply_new_orientation <- function(orientation_data,angle) {
    orientation_data = orientation_data - angle;
    
    less_neg_ninety = ! is.na(orientation_data) & orientation_data <= -90;
    orientation_data[less_neg_ninety] = orientation_data[less_neg_ninety] + 180;

    return(orientation_data)
}

find_FAAI <- function(orientations) {
    test_angles = test_dom_angles(orientations);
    best_angle = find_best_alignment_angle(test_angles);
    cor_orientation = apply_new_orientation(orientations,best_angle);
    best_FAAI = find_FAAI_from_orientation(cor_orientation);
    return(best_FAAI)
}

###########################################################
# Adhesion Birth Direction Processing
###########################################################

apply_new_orientation_360 <- function(orientation_data,angle) {
    orientation_data = orientation_data - angle;
    
    less_neg_180 = ! is.na(orientation_data) & orientation_data < -180;
    orientation_data[less_neg_180] = orientation_data[less_neg_180] + 360;

    return(orientation_data)
}

test_birth_directions <- function(orientation, search_resolution = 1) {
    # I'll include and then discard the last angle because 360 is the same as 0
    # degrees rotation in this case, but we need a consistant end point to allow
    # the search resolution to vary
    angles_to_test = seq(0,360,by=search_resolution)
    angles_to_test = angles_to_test[-length(angles_to_test)];
    
    results = list(x = angles_to_test, test_angles = angles_to_test);

    new_angle_FADI = c()
    mean_angle = c()
    median_angle = c()
    for (angle in angles_to_test) {
        new_orientation = apply_new_orientation_360(orientation,angle);
        mean_angle = c(mean_angle,mean(new_orientation, na.rm=T));
        median_angle = c(median_angle,median(new_orientation, na.rm=T));
        new_angle_FADI = c(new_angle_FADI, find_FADI_from_orientation(new_orientation));
    }
        
    results$y = new_angle_FADI;
    results$mean_angle = mean_angle;
    results$median_angle = median_angle;
    results$angle_FADI = new_angle_FADI;
    
    return(results)
}

find_FADI_from_orientation <- function(orientation_data) {
    return(180-sd(orientation_data, na.rm=T));
}

###########################################################
# Processing Single Adhesion Data
###########################################################

gather_all_single_adhesion_deviances <- function(sample_data, min.area=-Inf, min.data.points=2) {
    sample_data_filtered = filter_single_adhesion_alignment_data(sample_data, 
        min.area=min.area, min.data.points=min.data.points);
    overall_dev = adhesion_angle_deviance(sample_data_filtered$mat$filtered_orientation);
    
    #no single adhesion devs were calculated, no need for further processing,
    #return the empty results
    if (dim(overall_dev)[1] == 0) {
        return(overall_dev)
    }

    diff_from_dominant = c()
    for (i in 1:dim(overall_dev)[1]) {
        angle_set = sort(c(overall_dev$best_angle[i],sample_data$best_angle));
        temp = min(c(angle_set[2] - angle_set[1]),angle_set[1] + 180 - angle_set[2]);
        diff_from_dominant = c(diff_from_dominant, temp);
    }
    overall_dev$diff_from_dominant = diff_from_dominant

    return(overall_dev)
}

filter_single_adhesion_alignment_data <- function(align_data, min.data.points = 2, min.ratio = 3, 
	min.area = -Inf) {
 
    orientation = as.matrix(align_data$mat$orientation);
    ratio = as.matrix(align_data$mat$ratio);
    area = as.matrix(align_data$mat$area);
    
    above_ratio_limit = ! is.na(ratio) & ratio >= min.ratio
    above_area_limit = ! is.na(area) & area >= min.area

    above_all_limits = above_ratio_limit & above_area_limit;
    num_above_limits = rowSums(above_all_limits)
    passed_ad_nums = which(num_above_limits >= min.data.points)
    
	for (ad_num in 1:dim(orientation)[1]) {
		if (any(passed_ad_nums == ad_num)) {
			next;
		} else {
			orientation[ad_num,] = NA;
		}
	}

	orientation[! above_all_limits] = NA;
	
    align_data$mat$filtered_orientation = orientation;

    return(align_data);
}

adhesion_angle_deviance <- function(orientations,min.data.points) {
	passed_ads = which(rowSums(! is.na(orientations)) >= 1)
	mean_dev = c()
    num_pass_filter = c()
    best_angle_set = c()
	for (ad_num in passed_ads) {
		or_set = orientations[ad_num,];
		or_set = na.omit(or_set);
        
		angle_test = test_dom_angles(or_set);
		best_angle = find_best_alignment_angle(angle_test);
        best_angle_set = c(best_angle_set,best_angle);
        
        or_set_pre = or_set;
		or_set = apply_new_orientation(or_set, best_angle);

		diffs = abs(or_set[2:length(or_set)] - or_set[1]);
		mean_dev = c(mean_dev,mean(diffs));
        num_pass_filter = c(num_pass_filter,length(or_set));
	}
	return(data.frame(mean_dev = mean_dev, ad_num=passed_ads, 
        num_pass_filter=num_pass_filter, best_angle=best_angle_set))
}

###########################################################
# Spatial
###########################################################

find_dist_overlaps_and_orientations <- function(lin_ts_folder,min.ratio=3,
    min.overlap=10,output.file='FA_dist_orientation.Rdata') {

    centroid_x = read.csv(file.path(lin_ts_folder,'Centroid_x.csv'),header=F)
    centroid_y = read.csv(file.path(lin_ts_folder,'Centroid_y.csv'),header=F)

    major = read.csv(file.path(lin_ts_folder,'MajorAxisLength.csv'),header=F)
    minor = read.csv(file.path(lin_ts_folder,'MinorAxisLength.csv'),header=F)
    orientation = read.csv(file.path(lin_ts_folder,'Orientation.csv'),header=F)

    ratio = major/minor;
    low_ratio = !is.na(ratio) & ratio < min.ratio;

    centroid_x[low_ratio] = NaN;
    centroid_y[low_ratio] = NaN;
    orientation[low_ratio] = NaN;
    
    print('Done loading and filtering position/orientation data')

    data_summary = determine_mean_dist_between(centroid_x,centroid_y,orientation,min.overlap=min.overlap);
    if (! is.na(output.file)) {
        save(data_summary,file=file.path(lin_ts_folder,'..',output.file));
    }
    return(data_summary);
}

determine_mean_dist_between <- function(centroid_x,centroid_y,data_set,min.overlap=2) {
    ad_1 = c(); ad_2 = c();
    dists = c();
    or_diff = c();
    overlap_counts = c();

    ad_present = ! is.na(centroid_x);
    
    #only adhesions which are alive for at least the minimum overlap period
    #could pass the overlap requirement, so we find a list of those adhesions
    #here
    possible_ads = which(rowSums(ad_present) >= min.overlap);
    print(paste('Found', length(possible_ads), 'eligible adhesions.'))
    print('Starting Adhesions Comparisons')
    
    hits = 0;
    for (i in 1:length(possible_ads)) {
        ad_num = possible_ads[i];
        
        #progress message
        if (any(i == round(seq(length(possible_ads)/10,length(possible_ads),length=10)))) {
            print(paste('Done with ',i-1,'/',length(possible_ads)));
        }

        comparison_ads = possible_ads[possible_ads > ad_num];
        for (other_ad_num in comparison_ads) {
            overlap_count = sum(ad_present[ad_num,] & ad_present[other_ad_num,]);
            if (overlap_count >= min.overlap) {
                ad_1 = c(ad_1,ad_num);
                ad_2 = c(ad_2,other_ad_num);
                overlap_counts = c(overlap_counts,overlap_count);

                data_1 = rbind(centroid_x[ad_num,],centroid_y[ad_num,]);
                data_2 = rbind(centroid_x[other_ad_num,],centroid_y[other_ad_num,]);
                
                dists = c(dists,find_mean_dist(data_1,data_2));
                
                orientation_1 = as.numeric(data_set[ad_num,]);
                orientation_2 = as.numeric(data_set[other_ad_num,]);
                
                dom_angles = test_dom_angles(c(orientation_1,orientation_2));
                best_angle = find_best_alignment_angle(dom_angles);
                
                orientation_1 = apply_new_orientation(orientation_1,best_angle);
                orientation_2 = apply_new_orientation(orientation_2,best_angle);
                
                or_diff = c(or_diff,mean(abs(orientation_1 - orientation_2),na.rm=T))
                hits = hits + 1;
            }
        }
    }
    print(paste('Examined', hits,'overlapping adhesions.'))
    
    return(data.frame(ad_1=ad_1,ad_2=ad_2,dists = dists,
        overlap_counts = overlap_counts,
        or_diff=or_diff));
}

find_mean_dist <- function(data_1,data_2) {
    mean_dist = NA;
   
    overlap_indexes = !is.na(data_1[1,]) & !is.na(data_2[1,]);
    if (all(! overlap_indexes)) {
        return(mean_dist);
    }

    data_1 = data_1[,overlap_indexes];
    data_2 = data_2[,overlap_indexes];
    
    dists = c()
    for (i in 1:dim(data_1)[2]) {
        dists = c(dists, sqrt((data_1[1,i]-data_2[1,i])^2+(data_1[2,i]-data_2[2,i])^2))
    }
    
    mean_dist = mean(dists);
    return(mean_dist);
}

bin_distance_data <- function(dist_data,pixel_size = 0.1333,min.data.points=50) {
    temp = list();
    sum = 0;
    for (this_dist_bin in sort(unique(dist_data$dist_bin))) {
        this_dist_bin_set = subset(dist_data,dist_bin==this_dist_bin);
        sum = sum+dim(this_dist_bin_set)[1]
        
        if (length(this_dist_bin_set$dists) < min.data.points) {
            next;
        }

        temp$dist = c(temp$dist, mean(this_dist_bin_set$dists)*pixel_size);
        temp$n_count = c(temp$n_count, length(this_dist_bin_set$dists));
        temp$or_mean = c(temp$or_mean,mean(this_dist_bin_set$or_diff));
        temp$or_plus = c(temp$or_plus,t.test(this_dist_bin_set$or_diff,conf.level=0.95)$conf[2]);
        temp$or_minus = c(temp$or_minus,t.test(this_dist_bin_set$or_diff,conf.level=0.95)$conf[1]);
    }
    print(sum)
    return(temp)
}

###########################################################
# Rate and Angle Data
###########################################################

gather_rate_versus_angle_data_set <- function(kinetics_data) {
    align_file = file.path(kinetics_data$exp_dir,'FA_orientation.Rdata');
    
    var_name = load(align_file)
    align_data = get(var_name);
    
    #setting up variables
    single_ads_pos_x_ref = align_data$single_ads$best_angle;
    greater_90 = single_ads_pos_x_ref > 90;
    single_ads_pos_x_ref[greater_90] = 180 - single_ads_pos_x_ref[greater_90]
    
    single_ads_best_ref = apply_new_orientation(single_ads_pos_x_ref,align_data$best_angle);

    temp_birth = kinetics_data$exp_props$birth_i_num;
    temp_birth[is.na(temp_birth)] = 0;
    
    temp_death = kinetics_data$exp_props$death_i_num+1;
    temp_death[is.na(temp_death)] = max(temp_death,na.rm=T);
    longev_unsure = temp_death - temp_birth
    
    #putting the data set together
    combined_data = list()
    ad_nums = align_data$single_ads$ad_nums

    combined_data$ad_nums = ad_nums;
    combined_data$assembly_rate = kinetics_data$assembly$slope[ad_nums]
    combined_data$disassembly_rate = kinetics_data$disassembly$slope[ad_nums]

    combined_data$longevity_unsure = longev_unsure[ad_nums]
    combined_data$longevity = kinetics_data$exp_props$longevity[ad_nums]

    combined_data$angle_dev = single_ads_best_ref
    combined_data$overall_FAAI = rep(max(align_data$angle_search$angle_FAAI),length(ad_nums))
    combined_data$ad_FAAI = align_data$single_ads$FAAI
    
    combined_data = as.data.frame(combined_data)
    
    return(combined_data)
}

get_angle_data_set <- function(kinetics_set) {
    rate_angle_data = list()
    for (i in 1:length(kinetics_set)) {
        temp = gather_rate_versus_angle_data_set(kinetics_set[[i]])
        rate_angle_data = rbind(rate_angle_data, temp)
        # print(paste('Done with ',i,'/',length(kinetics_set),sep=''))
    }
    return(rate_angle_data)
}

split_angle_data <- function(rate_angle_data, angle=45) {
    split_data = list()

    split_data$middle_assembly = subset(rate_angle_data,
        !is.na(assembly_rate) & assembly_rate > 0 & abs(angle_dev) < angle)
    split_data$out_assembly = subset(rate_angle_data,
        !is.na(assembly_rate) & assembly_rate > 0 & abs(angle_dev) >= angle)

    split_data$middle_disassembly = subset(rate_angle_data,
        !is.na(disassembly_rate) & disassembly_rate > 0 & abs(angle_dev) < angle)
    split_data$out_disassembly = subset(rate_angle_data,
        !is.na(disassembly_rate) & disassembly_rate > 0 & abs(angle_dev) >= angle)

    split_data$middle_longev = subset(rate_angle_data, abs(angle_dev) < angle)
    split_data$out_longev = subset(rate_angle_data, abs(angle_dev) >= angle)
    
    return(split_data)
}

###########################################################
# Data Loading
###########################################################
load_all_areas <- function(alignment_models) {
    areas = c()
    for (align_file in alignment_models) {
        data_set = get(load(align_file));
        areas = c(areas, data_set$high_ratio$area);
        print(paste('Done loading:', align_file));
    }
    return(areas)
}

load_alignment_props <- function(alignment_models) {
    if (length(alignment_models) == 0) {
        print('Problem, no alignment models submitted.');
    }

    align_props = list()
    for (align_file in alignment_models) {
        data_set = get(load(align_file));
        
        if (!(any(names(data_set) == "FAAI"))) {
            print(paste('Problem with:', align_file, 'skipping.'));
            next;
        }

        align_props$best_FAAI = c(align_props$best_FAAI, data_set$FAAI);
        if (any(names(data_set) == "actual_best_angle")) {
            align_props$actual_best_angle = c(align_props$actual_best_angle, data_set$actual_best_angle);
            align_props$best_angle = c(align_props$best_angle, data_set$best_angle);
        } else {
            align_props$best_angle = c(align_props$best_angle, data_set$best_angle);
        }
        
        align_props$adhesion_count = c(align_props$adhesion_count,dim(data_set$high_ratio)[1])
        align_props$adhesion_count_per_time = c(align_props$adhesion_count/dim(data_set$mat$orientation)[2])

        align_props$small_FAAI = c(align_props$small_FAAI, data_set$area_results$small$FAAI)
        align_props$medium_FAAI = c(align_props$medium_FAAI, data_set$area_results$medium$FAAI)
        align_props$large_FAAI = c(align_props$large_FAAI, data_set$area_results$large$FAAI)

        align_props$align_file = c(align_props$align_file, align_file);

        angles = (data_set$high_ratio$orientation+90)*(pi/180)
        # area = data_set$high_ratio$area
        # align_props$FAO = c(align_props$FAO, find_FAO(angles, area))
        # align_props$noW_FAO = c(align_props$noW_FAO, find_FAO(angles))
        # browser()
        print(paste('Done loading:', align_file))
    }
    align_props = as.data.frame(align_props);
    return(align_props)
}

load_elongation_matrices <- function(alignment_models) {
    if (length(alignment_models) == 0) {
        print('Problem, no alignment models submitted.');
    }

    data_mats = list()
    index = 1
    for (align_file in alignment_models) {
        data_set = get(load(align_file));
        
        data_mats[[index]] = data_set
        index = index + 1
        print(paste('Done loading:', align_file))
    }
    return(data_mats)
}

find_FAO <- function(angles,areas=NA) {
    if (!is.na(areas[1])) {
        FAO = (weighted.mean(cos(2*angles),areas)^2+weighted.mean(sin(2*angles),areas)^2)^(1/2)
    } else {
        FAO = (mean(cos(2*angles))^2+mean(sin(2*angles))^2)^(1/2)
    }
    return(FAO)
}

################################################################################
# Main Command Line Program
################################################################################

args = commandArgs(TRUE);
if (length(args) != 0) {
    debug = FALSE;
    fixed_best_angle = NA
    min.ratio = 3

	#split out the arguments from the passed in parameters and assign variables 
	#in the current scope
    for (this_arg in commandArgs()) {
        split_arg = strsplit(this_arg,"=",fixed=TRUE)
        if (length(split_arg[[1]]) == 1) {
            assign(split_arg[[1]][1], TRUE);
        } else {
            assign(split_arg[[1]][1], split_arg[[1]][2]);
        }
    }
	
    class(fixed_best_angle) <- "numeric";
    if (exists('time_series_dir')) {
        output.dir = file.path(time_series_dir,'..','FAAI');
        dir.create(output.dir, showWarnings=F);

        start_time = proc.time();
        FA_orientation_data = gather_FA_orientation_data(time_series_dir,
            fixed_best_angle=fixed_best_angle, min.ratio=min.ratio, 
            diagnostic.figure=T,output.dir=output.dir);
        end_time = proc.time();
        
        write.table(t(FA_orientation_data$corrected_orientation),
                  file.path(output.dir,'FAAI_angles.csv'),
                  row.names=F,col.names=F,sep=',');

        print(paste('FA Orientation Runtime:',(end_time - start_time)[3]))
        
        # start_time = proc.time();
        # temp = find_dist_overlaps_and_orientations(time_series_dir);
        # end_time = proc.time();
        # print(paste('FA Dists/Orientation Runtime:',(end_time - start_time)[3]))
    }
}

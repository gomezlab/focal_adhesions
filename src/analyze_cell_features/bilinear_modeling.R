build_bilinear_models <- function(data,exp_props,min.phase.length=10,time.spacing=1) {
    
    #get a blank result to make sure we can add the proper number of blank
    #entries for adhesions which dont meet analysis criteria
    sample_model_results = fit_all_possible_log_models(list(values = 1:10,time = 1:10));
    
    models = list()
    
    start_elapse = proc.time()[3];

    for (i in 1:dim(data)[1]) {
        #assembly rate gathering
        only.data = na.omit(data[i,]);
        time.series = list(value=only.data,
            time=seq(0,along.with=only.data,by=time.spacing));
        if (! is.finite(data[i,1]) && 
            ! exp_props$split_birth_status[i] && 
            length(only.data) >= (2*min.phase.length)) {

            assembly_model_results = fit_all_possible_log_models(time.series, 
                min.phase.length=min.phase.length);
        } else {
            assembly_model_results = rep(NA,dim(sample_model_results)[2]);
            names(assembly_model_results) <- names(sample_model_results);
        }

        #disassembly rate gathering
        data.reverse = rev(data[i,]);
        only.data.reverse = na.omit(data.reverse);
        time.series.reverse = list(value=only.data.reverse,
            time=seq(0,along.with=only.data.reverse,by=time.spacing));

        if (! is.finite(data.reverse[1]) && 
            exp_props$death_status[i] && 
            length(only.data.reverse) >= (2*min.phase.length)) {
 
            disassembly_model_results = fit_all_possible_log_models(time.series.reverse, 
                min.phase.length=min.phase.length);
        } else {
            disassembly_model_results = rep(NA,dim(sample_model_results)[2]);
            names(disassembly_model_results) <- names(sample_model_results);
        }
        
        # browser()
        # if (is.na(assembly_model_results[1])) browser()
        
        # now to determine the best model fits, if either model set is all NA's,
        # that means that models were not built, so we pass along the appropriate
        # set to the best model determination function
        if (all(is.na(assembly_model_results)) && all(is.na(disassembly_model_results))) {
            best_assembly_model = assembly_model_results;
            best_disassembly_model = disassembly_model_results;
        } else if (all(is.na(assembly_model_results))) {
            best_assembly_model = assembly_model_results;
           
            best_indexes = find_optimum_model_indexes(disassembly=disassembly_model_results);
            best_disassembly_model = disassembly_model_results[best_indexes[2],];
        } else if (all(is.na(disassembly_model_results))) {
            best_disassembly_model = disassembly_model_results;
            
            best_indexes = find_optimum_model_indexes(assembly=assembly_model_results);
            best_assembly_model = assembly_model_results[best_indexes[1],];
        } else {
            best_indexes = find_optimum_model_indexes(assembly=assembly_model_results, 
                disassembly=disassembly_model_results);
            
            best_assembly_model = assembly_model_results[best_indexes[1],];
            best_disassembly_model = disassembly_model_results[best_indexes[2],];
        }

        models$assembly = rbind(models$assembly, best_assembly_model);
        models$disassembly = rbind(models$disassembly, best_disassembly_model);
        
        if (i %% round(dim(data)[1]/10) == 0) {
            current_elapse = proc.time()[3];
            elapsed_time = current_elapse - start_elapse;
            
            time_left = round(elapsed_time*((dim(data)[1]-i)/i))

            print(paste('Done with ', i, '/', dim(data)[1], ' adhesions (', 
                round(100*(i/dim(data)[1])), '%) ', time_left, ' seconds left',sep=''))
        }
    }

    models$assembly = as.data.frame(models$assembly);
    models$disassembly = as.data.frame(models$disassembly);
    
    print(paste('Built ', length(which(!is.na(models$assembly$length))), 
        ' assembly models, built ', length(which(!is.na(models$disassembly$length))), 
        ' disassembly models',sep=''))

    models
}

fit_all_possible_log_models <- function(time.series,min.phase.length=10) {
    time.series$value = time.series$value/time.series$value[1];
    time.series$value[time.series$value < 0] = 1E-5;

    data_summary = list();

    for (i in min.phase.length:length(time.series$value)) {
        this_model = lm(log(time.series$value[1:i]) ~ time.series$time[1:i]);
        model_summary = summary(this_model);
        
        data_summary$adj.r.squared = c(data_summary$adj.r.squared, model_summary$adj.r.squared);
        data_summary$p.value = c(data_summary$p.value, model_summary$coefficients[2,4]);
        data_summary$slope = c(data_summary$slope, coef(this_model)[2]);
        data_summary$length = c(data_summary$length, i);
    }

    data_summary = as.data.frame(data_summary);
}

find_optimum_model_indexes <- function(assembly=NULL,disassembly=NULL) {
    best_fit_indexes = c(NA, NA);
    
    if (is.null(disassembly) && is.null(assembly)) {
        return(best_fit_indexes);
    }

    if (is.null(disassembly)) {
        best_index = min(which(assembly$adj.r.squared == max(assembly$adj.r.squared)))
        best_fit_indexes[1] = best_index
    } else if (is.null(assembly)) {
        best_index = min(which(disassembly$adj.r.squared == max(disassembly$adj.r.squared)));
        best_fit_indexes[2] = best_index
    } else {
        r_sums = matrix(NA,length(assembly$length), length(disassembly$length));
        
        best_indexes = c();
        
        max_total_length = max(assembly$length);

        for (as_index in 1:dim(r_sums)[1]) {
            for (dis_index in 1:dim(r_sums)[2]) {
                #skip calculating R sum if the total length of the combination
                #is greater than the length of the time series set
                total_length = assembly$length[as_index] + disassembly$length[dis_index];
                if (total_length > max_total_length) {
                    next;
                }

                r_sums[as_index,dis_index] = assembly$adj.r.squared[as_index] + disassembly$adj.r.squared[dis_index]
            }
        }
        
        best_fit_indexes = which(max(r_sums,na.rm=T) == r_sums, arr.ind=T);
        
        #dealing with the unlikely case that there is more than one hit on the
        #highest summed R-squared value, fortunately, "which" returns the set of
        #indexes closest to the upper right corner first, which is the shortest
        #model set and also the one we want
        if (dim(best_fit_indexes)[1] > 1) {
            best_fit_indexes = best_fit_indexes[1,];
        }
    }

    best_fit_indexes
}

produce_rate_filters <- function(single.exp.data, min.r.sq=-Inf, max.p.val=0.05, pos.slope=TRUE) {
    filter_sets = list()
    
    # First we cycle through all the variables used to filter the assembly and
    # disassembly phases, collecting logic table describing which adhesions
    # fulfill which criteria
    vars_to_filter = c("assembly", "disassembly")
    for (var in vars_to_filter) {
        #apply a bonferroni correction to the maximum acceptable p-value calculation
        corrected.p.value = max.p.val / sum(! is.na(single.exp.data[[var]]$p.value));
        
        filter_sets[[var]]$good.r.sq = ! is.na(single.exp.data[[var]]$adj.r.squared) & single.exp.data[[var]]$adj.r.squared >= min.r.sq
        filter_sets[[var]]$low.p.val = ! is.na(single.exp.data[[var]]$p.value) & single.exp.data[[var]]$p.value < corrected.p.value 
        filter_sets[[var]]$pos.slope = ! is.na(single.exp.data[[var]]$slope) & single.exp.data[[var]]$slope > 0; 
    }
    
    # There are two variables that are unique to assembly and disassembly
    # (split birth events and deaths due to merges), we will keep all those in
    # the logic table "extra" and the in named variables so we can access the
    # named variables separated if needed
    filter_sets$assembly$not_split_birth = ! single.exp.data$exp_props$split_birth_status
    filter_sets$assembly$extra = filter_sets$assembly$not_split_birth
    
    filter_sets$disassembly$death_status = single.exp.data$exp_props$death_status
    filter_sets$disassembly$extra = filter_sets$disassembly$death_status
    
    # Now all the filters are cascaded to produce the final filter set, then
    # the pos.slope variable is checked and applied if requested
    final_filters = list()
    for (var in vars_to_filter) {
        final_filters[[var]] = (filter_sets[[var]]$good.r.sq & 
            filter_sets[[var]]$low.p.val & filter_sets[[var]]$extra);
    }

    if (pos.slope) {
        for (var in vars_to_filter) {
            final_filters[[var]] = (final_filters[[var]] & filter_sets[[var]]$pos.slope);
        }
    }

    final_filters$joint = final_filters$assembly & final_filters$disassembly
    
    for (filter_type in names(final_filters)) {
        final_filters[[filter_type]] = as.logical(final_filters[[filter_type]])
    }

    final_filters$filter_sets = filter_sets;
    
    return(final_filters)
}

write_assembly_disassembly_periods <- function(result, dir) {
	if (! file.exists(dir)) {
		dir.create(dir,recursive=TRUE)
	}
	
    rate_filters = produce_rate_filters(result);

	ad_nums = which(rate_filters$assembly)
	if (! is.null(ad_nums)) {
		rows_and_length = cbind(ad_nums, result$assembly$length[ad_nums]);
		write.table(rows_and_length,file=file.path(dir,'assembly_rows_lengths.csv'), sep=',', row.names=FALSE, col.names=FALSE)
	}
	
	ad_nums = which(! is.na(result$disassembly$length))
	if (! is.null(ad_nums)) {
		rows_and_length = cbind(ad_nums, result$disassembly$length[ad_nums]);
		write.table(rows_and_length,file=file.path(dir,'disassembly_rows_lengths.csv'), sep=',', row.names=FALSE, col.names=FALSE)
	}
}

################################################################################
# Main Program
################################################################################

args = commandArgs(TRUE);
if (length(args) != 0) {
    debug = FALSE;
    min_length = 10;
    time_spacing = 1;
    
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
	
    class(min_length) <- "numeric";
    class(time_spacing) <- "numeric";
    if (exists('data_dir') & exists('model_file')) {
        #######################################################################
        # Reading in data files
        #######################################################################
        if (file.exists(file.path(data_dir,'lin_time_series',model_file))) {
            data_set = as.matrix(read.csv(file.path(data_dir,'lin_time_series',model_file),header=F));
        } else {
            print(paste('Could not find model data file: ', file.path(data_dir,'lin_time_series',model_file)))
            stop()
        }

        if (file.exists(file.path(data_dir,'single_lin.csv'))) {
            exp_props = read.csv(file.path(data_dir,'single_lin.csv'));
        } else {
            print(paste('Could not find exp props file: ', file.path(data_dir,'single_lin.csv')))
            stop()
        }

        #######################################################################
        # Model Building and Output
        #######################################################################
        model = build_bilinear_models(data_set,exp_props, min.phase.length = min_length, 
            time.spacing = time_spacing)
        model$exp_props = exp_props
        model$exp_dir = data_dir
        model$exp_data = data_set
        #regexpr returns -1 when no hit is found
        if (regexpr("Average_adhesion_signal",model_file) != -1) {
            print('Outputing model assembly and disassembly periods')
            write_assembly_disassembly_periods(model,data_dir)	
        }

        R_model_file = sub(".csv$", ".Rdata", model_file ,perl=T)
        output_file = file.path(data_dir,'models',R_model_file);
        if (! file.exists(dirname(output_file))) {
            dir.create(dirname(output_file),recursive=TRUE);
        }
        save(model,file = output_file)
    }
}

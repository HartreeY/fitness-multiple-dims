include("core.jl")

# Simulation functions
# ------------------------------------------------

"""
Calculates average fitness and average hetero- and homozygosities in a deme.
"""
function muts_by_sel_neu(ms1,ms2,s_sel_coef,h_domin_coef,n_loci,sel_loci=[])
    len = length(ms1)
    muts1s = 0
    muts2s = 0
    muts3s = 0
    muts1ns = 0
    muts2ns = 0
    muts3ns = 0
    fits = []
    
    for i in 1:len
        muts_AA_sel = 0
        muts_Aa_sel = 0
        muts_AA_neu = 0
        muts_Aa_neu = 0
        new_fitness = 1.0

        for j in 1:n_loci
            if ms1[i][j]==true && ms2[i][j]==true
                if j in sel_loci
                    muts_AA_sel += 1
                    new_fitness *= 1 - s_sel_coef
                else
                    muts_AA_neu += 1
                end

            elseif ms1[i][j]==true || ms2[i][j]==true
                if j in sel_loci
                    muts_Aa_sel += 1
                    new_fitness *= 1 - h_domin_coef * s_sel_coef
                else
                    muts_Aa_neu += 1
                end
            end
        end

        push!(fits,new_fitness)
        muts1s += muts_AA_sel
        muts2s += muts_Aa_sel
        muts1ns += muts_AA_neu
        muts2ns += muts_Aa_neu
        muts3s += length(sel_loci) - muts_AA_sel - muts_Aa_sel
        muts3ns += n_loci - length(sel_loci) - muts_AA_neu - muts_Aa_neu
    end

    muts1s /= len
    muts2s /= len
    muts3s /= len
    muts1ns /= len
    muts2ns /= len
    muts3ns /= len
    return muts1s,muts2s,muts3s,muts1ns,muts2ns,muts3ns,fits
end

@inbounds function mutate(ms1,ms2,mut_rate,n_loci)
    get_mutation_random = rand(Poisson(mut_rate))
    @fastmath @inbounds for _ in 1:get_mutation_random
        pos_alter = sample(1:n_loci)

        if rand(1:2)==1
            ms1[pos_alter] = true
        else
            ms2[pos_alter] = true
        end
    end
end

@inbounds function crossover(ms1,ms2,n_loci)
    for j in 1:n_loci
        lr = rand(1:2)
        ms1[j] = lr==1 ? ms1[j] : ms2[j]
    end
end

@inbounds function mate(ind1,ind2,n_loci)
    new_loci = vcat(ind1[1:n_loci],ind2[1:n_loci])
    return new_loci
end

@inbounds function build_next_gen(pnt_wld_ms1,pnt_wld_ms2,pnt_wld_stats,pnt_meanf_wld=NaN,pnt_pops_wld=NaN,pnt_muts_AAsel_wld=NaN,pnt_muts_Aasel_wld=NaN,
    pnt_muts_aasel_wld=NaN,pnt_muts_AAneu_wld=NaN,pnt_muts_Aaneu_wld=NaN,pnt_muts_aaneu_wld=NaN;
    x_max_migr=NaN,y_max_migr=NaN,migr_mode=0,x_bottleneck=NaN,refl_walls=false)

    # Determine the number of offspring for each deme
    next_gen_pops = zeros(Int16,pnt_wld_stats["x_max"],pnt_wld_stats["y_max"])
    next_gen_posits = []
    fill!(next_gen_pops,-1)
    for x in 1:pnt_wld_stats["x_max"],y in 1:pnt_wld_stats["y_max"]
        if isassigned(pnt_wld_ms1,x,y) && length(pnt_wld_ms1[x,y])>0
            n_ppl_at_deme = length(pnt_wld_ms1[x,y])
            expected_offspring = n_ppl_at_deme * (pnt_wld_stats["r_prolif_rate"]/(1 + (n_ppl_at_deme*(pnt_wld_stats["r_prolif_rate"]-1))/pnt_wld_stats["k_capacity"]))
            next_gen_pops[x,y] =  rand(Poisson(expected_offspring))
            if next_gen_pops[x,y]>0
                push!(next_gen_posits,[x,y])
            end
        end
    end
    
    # Define the habitat (world) and the data arrays in the next generation
    wld_ms1_next = Array{Array{Array{Bool}}}(undef,pnt_wld_stats["x_max"],pnt_wld_stats["y_max"])
    wld_ms2_next = Array{Array{Array{Bool}}}(undef,pnt_wld_stats["x_max"],pnt_wld_stats["y_max"])
    mean_fitn_next = NaN
    pops_next = NaN
    muts_AAsel_next = NaN
    muts_Aasel_next = NaN
    muts_aasel_next = NaN
    muts_AAneu_next = NaN
    muts_Aaneu_next = NaN
    muts_aaneu_next = NaN
    all_birth_count = 0

    # Fill the next generation habitat
    meanf_out = false
    pops_out = false
    sel_out = false
    neu_out = false
    if pnt_meanf_wld isa Array{Float32, 3}
        meanf_out = true
        mean_fitn_next = Array{Float32}(undef,pnt_wld_stats["x_max"],pnt_wld_stats["y_max"])
        fill!(mean_fitn_next,-1)
    end
    if pnt_pops_wld isa Array{Int32, 3}
        pops_out = true
        pops_next = zeros(Int32,pnt_wld_stats["x_max"],pnt_wld_stats["y_max"])
    end
    if (pnt_muts_AAsel_wld isa Array{Float32, 3}) && (pnt_muts_Aasel_wld isa Array{Float32, 3}) && (pnt_muts_aasel_wld isa Array{Float32, 3})
        sel_out = true
        muts_AAsel_next = zeros(Float32,pnt_wld_stats["x_max"],pnt_wld_stats["y_max"])
        muts_Aasel_next = zeros(Float32,pnt_wld_stats["x_max"],pnt_wld_stats["y_max"])
        muts_aasel_next = zeros(Float32,pnt_wld_stats["x_max"],pnt_wld_stats["y_max"])
    end
    if (pnt_muts_AAneu_wld isa Array{Float32, 3}) && (pnt_muts_Aaneu_wld isa Array{Float32, 3}) && (pnt_muts_aaneu_wld isa Array{Float32, 3})
        neu_out = true
        muts_AAneu_next = zeros(Float32,pnt_wld_stats["x_max"],pnt_wld_stats["y_max"])
        muts_Aaneu_next = zeros(Float32,pnt_wld_stats["x_max"],pnt_wld_stats["y_max"])
        muts_aaneu_next = zeros(Float32,pnt_wld_stats["x_max"],pnt_wld_stats["y_max"])
    end
    

    for deme in next_gen_posits
        ms1_at_pos = pnt_wld_ms1[deme...]
        ms2_at_pos = pnt_wld_ms2[deme...]

        fitns = []
        cnt_res_AAsel,cnt_res_Aasel,cnt_res_aasel,cnt_res_AAneu,cnt_res_Aaneu,cnt_res_aaneu,fitns =
            muts_by_sel_neu(ms1_at_pos,ms2_at_pos,pnt_wld_stats["s_sel_coef"],pnt_wld_stats["h_domin_coef"],pnt_wld_stats["n_loci"],pnt_wld_stats["sel_loci"])
        
        sum_fitn = sum(fitns)
        fitns /= sum_fitn

        if meanf_out
            mean_fitn_next[deme...] = mean(fitns)
        end
        if sel_out
            muts_AAsel_next[deme...] = cnt_res_AAsel
            muts_Aasel_next[deme...] = cnt_res_Aasel
            muts_aasel_next[deme...] = cnt_res_aasel
        end
        if neu_out
            muts_AAneu_next[deme...] = cnt_res_AAneu
            muts_Aaneu_next[deme...] = cnt_res_Aaneu
            muts_aaneu_next[deme...] = cnt_res_aaneu
        end

        next_generation_size = next_gen_pops[deme...]
        
        if next_generation_size > 0
            birth_count = 0
            for _ in 1:next_generation_size
                mom_ms1 = wsample(ms1_at_pos,fitns)
                mom_ms2 = wsample(ms2_at_pos,fitns)
                dad_ms1 = wsample(ms1_at_pos,fitns)
                dad_ms2 = wsample(ms2_at_pos,fitns)

                gamete_mom_ms1 = copy(mom_ms1)
                gamete_dad_ms1 = copy(dad_ms1)
                gamete_mom_ms2 = copy(mom_ms2)
                gamete_dad_ms2 = copy(dad_ms2)

                crossover(gamete_mom_ms1,gamete_mom_ms2,pnt_wld_stats["n_loci"])
                crossover(gamete_dad_ms1,gamete_dad_ms2,pnt_wld_stats["n_loci"])
                mutate(gamete_mom_ms1,gamete_mom_ms2,pnt_wld_stats["mut_rate"],pnt_wld_stats["n_loci"])
                mutate(gamete_dad_ms1,gamete_dad_ms2,pnt_wld_stats["mut_rate"],pnt_wld_stats["n_loci"])

                if migr_mode == "4"
                    p_lat = 1
                    p_diag = 0
                elseif migr_mode == "buffon1"
                    p_lat = 2/pi
                    p_diag = 1/pi
                elseif migr_mode == "buffon2"
                    p_lat = 4/3/pi
                    p_diag = 1/3/pi
                elseif migr_mode == "buffon3"
                    p_lat = 0.4244132
                    p_diag = 0.21221
                elseif migr_mode == "8"
                    p_lat = 1/2
                    p_diag = 1/2
                elseif migr_mode == "1/2diag"
                    p_lat = 2/3
                    p_diag = 1/3
                end

                move_x = 0
                move_y = 0
                migr_res = rand()
                if rand()<pnt_wld_stats["migr_rate"] && migr_res < p_lat+p_diag
                    if migr_res < p_lat
                        dir = sample(MIGR_DIRS_4)
                    elseif migr_res < p_lat+p_diag
                        dir = sample(MIGR_DIRS_8)
                    end

                    # Raw migration results
                    move_x = dir[1]
                    move_y = dir[2]

                    # Nullify migration on certain conditions
                    if !isnan(x_bottleneck) && (deme[1]+move_x==x_bottleneck && deme[2]+move_y!=ceil(pnt_wld_stats["y_max"]/2)) # bottleneck barrier check
                        move_x = 0
                        move_y = 0
                    else
                        if deme[1]+move_x > x_max_migr || deme[1]+move_x < 1 # burn-in area check
                            move_x = refl_walls ? -move_x : 0
                        end
                        if deme[2]+move_y > pnt_wld_stats["y_max"] || deme[2]+move_y < 1
                            move_y = refl_walls ? -move_y : 0
                        end
                    end
                end

                if !isassigned(wld_ms1_next,deme[1]+move_x,deme[2]+move_y)
                    wld_ms1_next[deme[1]+move_x,deme[2]+move_y] = []
                    wld_ms2_next[deme[1]+move_x,deme[2]+move_y] = []
                end
                push!(wld_ms1_next[deme[1]+move_x,deme[2]+move_y],gamete_mom_ms1)
                push!(wld_ms2_next[deme[1]+move_x,deme[2]+move_y],gamete_dad_ms2)

                birth_count += 1
                all_birth_count += 1
            end
            
            if pops_out
                pops_next[deme...] = birth_count
            end
        end
    end
    
    #pnt_wld_ms1 = wld_ms1_next
    #pnt_wld_ms2 = wld_ms2_next
    return wld_ms1_next,wld_ms2_next,mean_fitn_next, pops_next, muts_AAsel_next, muts_Aasel_next, muts_aasel_next, muts_AAneu_next, muts_Aaneu_next, muts_aaneu_next
end

function create_empty_world(x_max=DEF_X_MAX,y_max=DEF_Y_MAX;name=Dates.format(Dates.now(), dateformat"yyyy-mm-dd_HH-MM-SS"),k_capacity=DEF_K_CAPACITY,
    r_prolif_rate=DEF_R_PROLIF_RATE,n_loci=DEF_N_LOCI,n_sel_loci=DEF_N_SEL_LOCI,
    mut_rate=DEF_MUT_RATE,migr_rate=DEF_MIGR_RATE,migr_dirs=DEF_MIGR_DIRS,s_sel_coef=DEF_S_SEL_COEF,h_domin_coef=DEF_H_DOMIN_COEF,prop_of_del_muts=DEF_PROP_OF_DEL_MUTS)

    wld_ms1 = Array{Array{Array{Bool}}}(undef,x_max,y_max) # array of left (in a pair) monosomes ("ms") of all individuals in space
    wld_ms2 = Array{Array{Array{Bool}}}(undef,x_max,y_max) # array of right (in a pair) monosomes ("ms") of all individuals in space

    wld_stats = Dict(
        "name" => name,
        "x_max" => x_max,
        "y_max" => y_max,
        "k_capacity" => k_capacity,
        "r_prolif_rate" => r_prolif_rate,
        "n_loci" => n_loci,
        "n_sel_loci" => n_sel_loci,
        "mut_rate" => mut_rate,
        "migr_rate" => migr_rate,
        "migr_dirs" => migr_dirs,
        "s_sel_coef" => s_sel_coef,
        "h_domin_coef" => h_domin_coef,
        "prop_of_del_muts" => prop_of_del_muts

        #"rangeexps" => []
    )

    return wld_ms1,wld_ms2,wld_stats
end

function fill_random_demes(pnt_wld_ms1,pnt_wld_ms2,pnt_wld_stats,x_max_fill,y_max_fill,n_demes_to_fill=DEF_N_DEMES_STARTFILL)

    possible_init_coords = [collect(x) for x in Iterators.product(1:x_max_fill, 1:y_max_fill)]
    init_coords = sample(possible_init_coords,n_demes_to_fill;replace=false)
    pnt_wld_stats["sel_loci"] = randperm(pnt_wld_stats["n_loci"])[1:pnt_wld_stats["n_sel_loci"]]

    for coord in init_coords
        if !isassigned(pnt_wld_ms1,coord...)
            pnt_wld_ms1[coord...] = []
            pnt_wld_ms2[coord...] = []
        end
        for i in 1:pnt_wld_stats["k_capacity"]
            push!(pnt_wld_ms1[coord...],falses(pnt_wld_stats["n_loci"]))
            push!(pnt_wld_ms2[coord...],falses(pnt_wld_stats["n_loci"]))
        end
    end

    pnt_wld_stats["x_startfill"] = x_max_fill
    pnt_wld_stats["y_startfill"] = y_max_fill
    pnt_wld_stats["n_demes_startfill"] = n_demes_to_fill
end

"""
Simulates an axial range expansion, in which a population expands in the positive x direction (after an optional burn-in phase).
If no world is provided, generates a world and seeds it with ```DEF_N_DEMES_STARTFILL``` demes filled with individuals.

---

```n_gens_burnin```: duration of the burn-in phase, used to reach mutation-selection equilibrium

```n_gens_exp```: duration of the expansion

```x_max_burnin```: the outward x-coordinate bound for migration during burn-in

```x_max_exp```: the outward x-coordinate bound for migration during the expansion

```y_max```: the upper y-coordinate bound (lower bound is always **0** currently)

```migr_mode```: mode of migration. Possible values:
- **4** - lateral directions only
- **6** - hexagonal grid
- **8** - lateral and diagonal
- **diag1/2** - lateral and half-weighted diagonal
- **buffon1** - equidistant Buffon-Laplace (see documentation)
- **buffon2** - uniform Buffon-Laplace
- **buffon3** - inv.proportional Buffon-Laplace

`data_to_generate`: string of letters representing different data to output. Possible values:
- **F** - deme-average fitness (**meanf**)
- **P** - deme populations (**pops**)
- **S** - deme-average number of homo- and heterozygous selected loci (**AAsel**, **Aasel** and **aasel**)
- **M** - deme-average number of homo- and heterozygous neutral loci (**AAneu**, **Aaneu** and **aaneu**)

If starting from existing world, also provide:

```wld_ms1```: world left monosome array

```wld_ms2```: world right monosome array

```wld_stats```: world stats Dict

---

"""
function rangeexp_axial(n_gens_burnin=DEF_N_GENS_BURNIN,n_gens_exp=DEF_N_GENS_EXP;x_max_burnin=DEF_X_MAX_BURNIN,x_max_exp=DEF_X_MAX_EXP,y_max=DEF_Y_MAX,migr_mode=DEF_MIGR_MODE,
    data_to_generate=DEF_DATA_TO_GENERATE,wld_ms1=NaN,wld_ms2=NaN,wld_stats=NaN) # expansion along x model 2

    meanf_wld = NaN
    pops_wld = NaN
    muts_AAsel_wld = NaN
    muts_Aasel_wld = NaN
    muts_aasel_wld = NaN
    muts_AAneu_wld = NaN
    muts_Aaneu_wld = NaN
    muts_aaneu_wld = NaN

    if !(wld_ms1 isa Array{Float32, 3})
        #println("No world provided. Creating a new world.")
        wld_ms1,wld_ms2,wld_stats = create_empty_world(x_max_exp,y_max)
        fill_random_demes(wld_ms1,wld_ms2,wld_stats,Int(x_max_exp/20),y_max)
    end

    if occursin("F", data_to_generate)
        meanf_wld = Array{Float32}(undef, wld_stats["x_max"], wld_stats["y_max"], 0)
    end
    if occursin("P", data_to_generate)
        pops_wld = Array{Int32}(undef, wld_stats["x_max"], wld_stats["y_max"], 0)
    end
    if occursin("S", data_to_generate)
        muts_AAsel_wld = Array{Float32}(undef, wld_stats["x_max"], wld_stats["y_max"], 0)
        muts_Aasel_wld = Array{Float32}(undef, wld_stats["x_max"], wld_stats["y_max"], 0)
        muts_aasel_wld = Array{Float32}(undef, wld_stats["x_max"], wld_stats["y_max"], 0)
    end
    if occursin("M", data_to_generate)
        muts_AAneu_wld = Array{Float32}(undef, wld_stats["x_max"], wld_stats["y_max"], 0)
        muts_Aaneu_wld = Array{Float32}(undef, wld_stats["x_max"], wld_stats["y_max"], 0)
        muts_aaneu_wld = Array{Float32}(undef, wld_stats["x_max"], wld_stats["y_max"], 0)
    end

    n_gens_total = n_gens_burnin+n_gens_exp
    @inbounds for g in 1:n_gens_total
        if g<=n_gens_burnin
            _x_max_used = x_max_burnin
        else
            _x_max_used = x_max_exp
        end
        wld_ms1,wld_ms2,mean_fitn_next,pops_next,muts_AAsel_next,muts_Aasel_next,muts_aasel_next,muts_AAneu_next,
        muts_Aaneu_next,muts_aaneu_next = build_next_gen(wld_ms1,wld_ms2,wld_stats,meanf_wld,pops_wld,muts_AAsel_wld,muts_Aasel_wld,muts_aasel_wld,muts_AAneu_wld,
        muts_Aaneu_wld,muts_aaneu_wld;x_max_migr=_x_max_used,y_max_migr=DEF_Y_MAX,migr_mode=migr_mode,x_bottleneck=x_max_burnin*2)
        if occursin("F", data_to_generate)
            meanf_wld = cat(meanf_wld, mean_fitn_next, dims=3)
        end
        if occursin("P", data_to_generate)
            pops_wld = cat(pops_wld, pops_next, dims=3)
        end
        if occursin("S", data_to_generate)
            muts_AAsel_wld = cat(muts_AAsel_wld, muts_AAsel_next, dims=3)
            muts_Aasel_wld = cat(muts_Aasel_wld, muts_Aasel_next, dims=3)
            muts_aasel_wld = cat(muts_aasel_wld, muts_aasel_next, dims=3)
        end
        if occursin("M", data_to_generate)
            muts_AAneu_wld = cat(muts_AAneu_wld, muts_AAneu_next, dims=3)
            muts_Aaneu_wld = cat(muts_Aaneu_wld, muts_Aaneu_next, dims=3)
            muts_aaneu_wld = cat(muts_aaneu_wld, muts_aaneu_next, dims=3)
        end
    end

#=  append!(wld_stats["rangeexps"],Dict(
        "x_max_burnin" => x_max_burnin,
        "y_max_burnin" => DEF_Y_MAX,
        "n_gens_burnin" => n_gens_burnin,
        "n_gens_exp" => n_gens_exp,
        "n_gens" => n_gens_total)) =#
    wld_stats["x_max_burnin"] = x_max_burnin
    wld_stats["y_max_burnin"] = DEF_Y_MAX
    wld_stats["n_gens_burnin"] = n_gens_burnin
    wld_stats["n_gens_exp"] = n_gens_exp
    wld_stats["n_gens"] = n_gens_total
    
#=     res = []
    function needed_data(symb,arr,res)
        if occursin("P", data_to_generate)
            push!(res,Ref(arr))
        end
    end
    needed_data("P",pops_wld) =#
    return Dict("stats"=>wld_stats,"meanf"=>meanf_wld,"pops"=>pops_wld,"AAsel"=>muts_AAsel_wld,"Aasel"=>muts_Aasel_wld,
        "aasel"=>muts_aasel_wld,"AAneu"=>muts_AAneu_wld,"Aaneu"=>muts_Aaneu_wld,"aaneu"=>muts_aaneu_wld)
end

# Plotting functions
# ------------------------------------------------

"""
Shows an animated heatmap of ```obj``` from ```gen_start``` to ```gen_end```.

---

```obj```: 2-dimensional array of data by deme

```gen_start```: start generation

```gen_end```: end generation

```slow_factor```: number of animation frames per generation

```clim```: color bounds (Plots.jl's clim parameter)

```log_base```: if not **-1**, color shows log values with this as base

---

"""
function re_heatmap(obj,gen_start=1,gen_end=DEF_N_GENS_BURNIN+DEF_N_GENS_EXP,slow_factor=1;clim=:default,log_base=-1)
    @gif for i=gen_start:(gen_end*slow_factor-1)
        gen_no = trunc(Int,i/slow_factor)+1
        if log_base>0 && log_base==1
            heatmap(log.(log_base,obj[:,:,gen_no]'),ylabel="Generation $gen_no",size=(1000,250),clim=clim)
        else
            heatmap(obj[:,:,gen_no]',ylabel="Generation $gen_no",size=(1000,250),clim=clim)
        end
    end
end

"""
Shows population data of ```re``` from ```gen_start``` to ```gen_end```.

---

```re```: range expansion results dictionary

```gen_start```: start generation

```gen_end```: end generation

```slow_factor```: number of animation frames per generation

```clim```: color bounds (Plots.jl's clim parameter)

```log_base```: if not **-1**, color shows log values with this as base

---

"""
function re_heatmap_pops(re,gen_start=1,gen_end=re["stats"]["n_gens"],slow_factor=1;clim=(0,re["stats"]["k_capacity"]),log_base=-1)
    re_heatmap(re["pops"],gen_start,gen_end,slow_factor;clim=clim,log_base=log_base)
end

function re_heatmap_meanf(re::Dict,gen_start=1,gen_end=re["stats"]["n_gens"],slow_factor=1;clim=(0,1),log_base=-1)
    re_heatmap(re["meanf"],gen_start,gen_end,slow_factor;clim=clim,log_base=log_base)
end
function re_heatmap_meanf(obj::Array,gen_start,gen_end,slow_factor=1;clim=(0,1),log_base=-1)
    re_heatmap(obj,gen_start,gen_end,slow_factor;clim=clim,log_base=log_base)
end

function re_heatmap_AAsel(re,gen_start=1,gen_end=re["stats"]["n_gens"],slow_factor=1;clim=(0,length(re["stats"]["sel_loci"])),log_base=-1)
    re_heatmap(re["AAsel"],gen_start,gen_end,slow_factor;clim=clim,log_base=log_base)
end

function re_heatmap_Aasel(re,gen_start=1,gen_end=re["stats"]["n_gens"],slow_factor=1;clim=(0,length(re["stats"]["sel_loci"])),log_base=-1)
    re_heatmap(re["Aasel"],gen_start,gen_end,slow_factor;clim=clim,log_base=log_base)
end

function re_heatmap_aasel(re,gen_start=1,gen_end=re["stats"]["n_gens"],slow_factor=1;clim=(0,length(re["stats"]["sel_loci"])),log_base=-1)
    re_heatmap(re["aasel"],gen_start,gen_end,slow_factor;clim=clim,log_base=log_base)
end

function re_heatmap_AAneu(re,gen_start=1,gen_end=re["stats"]["n_gens"],slow_factor=1;clim=(0,re["stats"]["n_loci"]-length(re["stats"]["sel_loci"])),log_base=-1)
    re_heatmap(re["AAneu"],gen_start,gen_end,slow_factor;clim=clim,log_base=log_base)
end

function re_heatmap_Aaneu(re,gen_start=1,gen_end=re["stats"]["n_gens"],slow_factor=1;clim=(0,re["stats"]["n_loci"]-length(re["stats"]["sel_loci"])),log_base=-1)
    re_heatmap(re["Aaneu"],gen_start,gen_end,slow_factor;clim=clim,log_base=log_base)
end

function re_heatmap_aaneu(re,gen_start=1,gen_end=re["stats"]["n_gens"],slow_factor=1;clim=(0,re["stats"]["n_loci"]-length(re["stats"]["sel_loci"])),log_base=-1)
    re_heatmap(re["aaneu"],gen_start,gen_end,slow_factor;clim=clim,log_base=log_base)
end

# Functions pertaining to the expansion front
# ------------------------------------------------

"""
Finds the average value of ```obj``` between all demes at the expansion front of ```re```.

---

```re```: range expansion results dictionary

```obj```: 2-dimensional array of data by deme

```leqzero```: if **true**, approach only from one side (i.e. from the positive direction in axial expansions)

```oneside```: if **true**, approach only from one side (i.e. from the positive direction in axial expansions)

```divide```: if **true**, find average

---

"""
function average_front(re,obj="meanf";leqzero=false,oneside=false,divide=true)
    average_front(re[obj],re["stats"]["n_gens"],re["stats"]["x_max"],re["stats"]["y_max"];leqzero=leqzero,oneside=oneside,divide=divide)
end

function average_front(data_array,n_gens,x_max,y_max;leqzero=false,oneside=false,divide=true)
    front_array = Array{Float64}(undef,0)
    for j in 1:n_gens
        sum_total = 0
        cnt = 0
        # scanning every y: side 1
        for _y in 1:y_max
            frontier_x = x_max
            while frontier_x != 1 && ((leqzero && data_array[frontier_x,_y,j] <= 0) || (!leqzero && data_array[frontier_x,_y,j] < 0))
                frontier_x -= 1
            end
            if data_array[frontier_x,_y,j]>0
                sum_total += data_array[frontier_x,_y,j]
                cnt += 1
            end
        end
        # scanning every y: side 2
        if !oneside
            for _y in 1:y_max
                frontier_x = 1
                while frontier_x != x_max && ((leqzero && data_array[frontier_x,_y,j] <= 0) || (!leqzero && data_array[frontier_x,_y,j] < 0))
                    frontier_x += 1
                end
                if data_array[frontier_x,_y,j]>0
                    sum_total += data_array[frontier_x,_y,j]
                    cnt += 1
                end
            end
        end
        mean_both_sides_y = sum_total
        if divide
            mean_both_sides_y /= cnt
        end

        if !oneside
            sum_total = 0
            cnt = 0
            # scanning every x: side 1
            for _x in 1:x_max
                frontier_y = y_max
                while frontier_y != 1 && ((leqzero &&  data_array[_x,frontier_y,j] <= 0) || (!leqzero && data_array[_x,frontier_y,j] < 0))
                    frontier_y -= 1
                end
                if data_array[_x,frontier_y,j]>0
                    sum_total += data_array[_x,frontier_y,j]
                    cnt += 1
                end
            end
            # scanning every x: side 2
            for _x in 1:x_max
                frontier_y = 1
                while frontier_y != y_max && ((leqzero && data_array[_x,frontier_y,j] <= 0) || (!leqzero && data_array[_x,frontier_y,j] < 0))
                    frontier_y += 1
                end
                if data_array[_x,frontier_y,j]>0
                    sum_total += data_array[_x,frontier_y,j]
                    cnt += 1
                end
            end
            if divide
                mean_both_sides_x = sum_total/cnt
            end
            front_array = cat(front_array,(mean_both_sides_x+mean_both_sides_y)/2, dims=1)
        else
            front_array = cat(front_array,mean_both_sides_y, dims=1)
        end
    end
    return front_array
end

"""
Finds the front array of ```obj``` in ```re```.

---

```re```: range expansion results dictionary

```obj```: 2-dimensional array of data by deme

```oneside```: if **true**, approach only from one side (i.e. from the positive direction in axial expansions)

---

"""
function front_array(re,obj="meanf";oneside=false)
    front_array(re[obj],re["stats"]["n_gens"],re["stats"]["x_max"],re["stats"]["y_max"];oneside=oneside)
end

function front_array(data_array,n_gens,x_max,y_max;oneside=false)
    front_arr = zeros(x_max,y_max,n_gens)
    for j in 1:n_gens
        # scanning every y: side 1
        for _y in 1:y_max
            frontier_x = x_max
            while frontier_x != 1 && data_array[frontier_x,_y,j] < 0
                frontier_x -= 1
            end
            if data_array[frontier_x,_y,j]>0
                front_arr[frontier_x,_y,j]=data_array[frontier_x,_y,j]
            end
        end
        # scanning every y: side 2
        if !oneside
            for _y in 1:y_max
                frontier_x = 1
                while frontier_x != x_max && data_array[frontier_x,_y,j] < 0
                    frontier_x += 1
                end
                if data_array[frontier_x,_y,j]>0
                    front_arr[frontier_x,_y,j]=data_array[frontier_x,_y,j]
                end
            end
        end

        if !oneside
            # scanning every x: side 1
            for _x in 1:x_max
                frontier_y = y_max
                while frontier_y != 1 && data_array[_x,frontier_y,j] < 0
                    frontier_y -= 1
                end
                if data_array[_x,frontier_y,j]>0
                    front_arr[_x,frontier_y,j]=data_array[_x,frontier_y,j]
                end
            end
            # scanning every x: side 2
            for _x in 1:x_max
                frontier_y = 1
                while frontier_y != y_max && data_array[_x,frontier_y,j] < 0
                    frontier_y += 1
                end
                if data_array[_x,frontier_y,j]>0
                    front_arr[_x,frontier_y,j]=data_array[_x,frontier_y,j]
                end
            end
        end
    end
    return front_arr
end

# mean front fitness (or other data)
"""
Normalises ```obj``` in ```re``` using the "maximum normalisation" method: after the last burn-in generation, divide by the maximum of each generation.

---

```re```: range expansion results dictionary

```obj```: 2-dimensional array of data by deme

---

"""
function norm_maximum(re,obj="meanf")
    norm_maximum(re[obj],re["stats"]["n_gens_burnin"],re["stats"]["n_gens_exp"])
end

function norm_maximum(data_array,n_gens_burnin,n_gens_exp)
    normal_array = copy(data_array)
    for j in 1:n_gens_exp
        gen_max = maximum(data_array[:,:,n_gens_burnin+j])
        normal_array[:,:,n_gens_burnin+j] /= gen_max
    end
    return normal_array
end

"""
Normalises ```obj``` in ```re``` using the "maximum normalisation" method: after the last burn-in generation, divide by the constant value of average fitness over all demes at the (last burn-in generation+1)=onset generation

---

```re```: range expansion results dictionary

```obj```: 2-dimensional array of data by deme

```offset``` - offset from the onset generation

---

"""
function norm_onset_mean(re::Dict,obj::String="meanf",offset=0)
    norm_onset_mean(re[obj],re["stats"]["n_gens_burnin"],offset=offset)
end

function norm_onset_mean(data_array::Array,n_gens_burnin::Int,offset=0)
    normal_array = copy(data_array)

    sum = 0
    count = 0
    for u in data_array[:,:,n_gens_burnin+1+offset]
        if u > 0
            sum += u
            count += 1
        end
    end
    gen_average = sum/count

    normal_array[:,:,n_gens_burnin+1:end] /= gen_average
    return normal_array
end

#= function normalise_front_by_onset_mean(average_1d_array)
    normal_array = copy(average_1d_array)
    normal_array[BURN_IN_GEN_N+1:end] /= average_1d_array[BURN_IN_GEN_N+1]
    return normal_array
end

function normalise_front_by_max(average_1d_array,meanf_array)
    normal_array = copy(average_1d_array)
    for j in 1:(TOTAL_GEN_N-BURN_IN_GEN_N)
        gen_max = maximum(meanf_array[:,:,BURN_IN_GEN_N+j])
        normal_array[BURN_IN_GEN_N+j] /= gen_max
    end
    return normal_array
end

function find_front_array_muts(data_array,muts_array;oneside=false)
    res_muts = zeros(Float32,y_max,n_gen)
    for j in 1:n_gen
        # scanning every y: side 1

        for _y in 1:y_max
            frontier_x = x_max
            while frontier_x != 1 && data_array[frontier_x,_y,j] < 0
                frontier_x -= 1
            end
            if data_array[frontier_x,_y,j]>0
                res_muts[_y,j]=muts_array[frontier_x,_y,j]
            end
        end
        # scanning every y: side 2
        # add later
    end
    return res_muts
end =#

vc(x) = cat(eachslice(x, dims=4)...,dims=2)

function re_get_avrel(data::Array,x,gen,denom)
    nd = ndims(data)
    if nd==4
        return mean(vc(data)[x,:,gen])/denom
    elseif nd==3
        return mean(data[x,:,gen])/denom
    else
        println("Wrong data type.")
    end
end
function re_get_avrel(re::Dict,dataname::String,x,gen=Int(re["stats"]["n_gens"]);sel=true)
    denom = sel ? re["stats"]["n_sel_loci"] : re["stats"]["n_loci"]-re["stats"]["n_sel_loci"]
    return re_get_avrel(re[dataname],x,gen,denom)
end
function re_get_avrelAAsel(re::Dict,x,gen=re["stats"]["n_gens"])
    return re_get_avrel(re,"AAsel",x,gen;sel=true)
end
function re_get_avrelAasel(re::Dict,x,gen=re["stats"]["n_gens"])
    return re_get_avrel(re,"Aasel",x,gen;sel=true)
end
function re_get_avrelaasel(re::Dict,x,gen=re["stats"]["n_gens"])
    return re_get_avrel(re,"aasel",x,gen;sel=true)
end
function re_get_avrelAAneu(re::Dict,x,gen=re["stats"]["n_gens"])
    return re_get_avrel(re,"AAneu",x,gen;sel=false)
end
function re_get_avrelAaneu(re::Dict,x,gen=re["stats"]["n_gens"])
    return re_get_avrel(re,"Aaneu",x,gen;sel=false)
end
function re_get_avrelaaneu(re::Dict,x,gen=re["stats"]["n_gens"])
    return re_get_avrel(re,"aaneu",x,gen;sel=false)
end

function re_plot_avrelselneu(re::Dict,dataname::String,x_range=(1:Int(re["stats"]["x_max"]));x_scale_factor=1,sel=true,overlay=false)
    nd = ndims(re[dataname*"sel"])
    if nd==4
        data1 = vc(re[dataname*"sel"])
        data2 = vc(re[dataname*"neu"])
    else
        data1 = re[dataname*"sel"]
        data2 = re[dataname*"neu"]
    end
    t = [re_get_avrel(data1,j,Int(re["stats"]["n_gens"]),re["stats"]["n_sel_loci"]) for j in x_range]
    t2 = [re_get_avrel(data2,j,Int(re["stats"]["n_gens"]),re["stats"]["n_loci"]-re["stats"]["n_sel_loci"]) for j in x_range]

    if haskey(re["stats"],"name")
        lbl1 = re["stats"]["name"]*"[selected $dataname]"
        lbl2 = re["stats"]["name"]*"[neutral $dataname]"
    else
        lbl1 = "selected $dataname"
        lbl2 = "neutral $dataname"
    end

    if overlay
        plot!(x_range*x_scale_factor,t,label=lbl1,xlabel="x")
    else
        plot(x_range*x_scale_factor,t,label=lbl1,xlabel="x")
    end
    plot!(x_range*x_scale_factor,t2,label=lbl2)
end

function re_plot_avrelselneu!(re::Dict,dataname::String,x_range=(1:Int(re["stats"]["x_max"]));x_scale_factor=1,sel=true,overlay=false)
    re_plot_avrelselneu(re,dataname,x_range;x_scale_factor=x_scale_factor,sel=sel,overlay=true)
end
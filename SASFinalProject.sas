/* ============================================================
   streaming services project — full working sas 9.4 script
   (sas/stat 15.1 compatible)
   pca (q1-q6) -> ward clustering -> mca (indicator matrix) -> discrim
   then anova/means + chi-square
   ============================================================ */

/* -------------------------------
   0) import
   ------------------------------- */
proc import datafile="c:\users\bbsstudent\downloads\statistics project\streaming services-project.xlsx"
    out=work.streaming_raw
    dbms=xlsx
    replace;
    getnames=yes;
run;

proc contents data=streaming_raw; run;

/* -------------------------------
   1) cleaning + variable assignment
   (variable names match your IMPORT notes)
   ------------------------------- */
data streaming_cleaned;
    set streaming_raw;

    id_user = _n_;

    /* qualitative variables (cleaned copies) */
    platform = propcase(strip(_1__Which_platforms_do_you_usual));
    freq     = propcase(strip(_2__How_often_do_you_watch_conte));
    spend    = strip(_3__How_much_do_you_spend_on_sub);
    device   = propcase(strip(_4__Which_device_do_you_use_most));

    gender         = propcase(strip('_1___Gender'n));
    age            = strip('_2__Age'n);
    occupation     = propcase(strip('_3__What_is_your_occupation_'n));
    educationlevel = propcase(strip('_4__Education_Level'n));

    /* likert (attitudes) */
    q1 = '_1_The_service_has_better_offers'n;
    q2 = '_2__The_subscription_has_a_low_p'n;
    q3 = '_3__There_is_a_wide_variety_of_m'n;
    q4 = '_4__It_saves_time_compared_to_lo'n;
    q5 = '_5__Watching_is_a_relaxing_leisu'n;
    q6 = '_6__It_allows_me_to_watch_conten'n;

    /* streaming usage */
    use_streaming = upcase(strip(_1__Do_you_use_online_streaming));
run;

/* -------------------------------
   2) keep only streaming users + remove missing likert
   ------------------------------- */
data streaming_users;
    set streaming_cleaned;
    if use_streaming = 'YES';
    if nmiss(q1,q2,q3,q4,q5,q6) > 0 then delete;
run;

proc sql;
select count(*) as n_streaming_users from streaming_users;
quit;

proc means data=streaming_users;
    var q1-q6;
run;

/* -------------------------------
   3) standardize + pca
   ------------------------------- */
proc standard data=streaming_users mean=0 std=1 out=streaming_std;
    var q1-q6;
run;

proc princomp data=streaming_std out=pca_scores plots=all;
    var q1-q6;
run;

/* merge pca scores back */
proc sort data=streaming_users; by id_user; run;
proc sort data=pca_scores;      by id_user; run;

data pca_full;
    merge pca_scores streaming_users;
    by id_user;
run;

/* -------------------------------
   4) hierarchical clustering (ward) on prin1 prin2
   ------------------------------- */
proc cluster data=pca_full method=ward outtree=tree plots=dendrogram;
    var prin1 prin2;
    id id_user;
run;

proc tree data=tree nclusters=3 out=clusters_h;
    id id_user;
run;

proc freq data=clusters_h;
    tables cluster;
run;

/* merge clusters back */
proc sort data=clusters_h;      by id_user; run;
proc sort data=streaming_users; by id_user; run;

data clusters_full;
    merge clusters_h streaming_users;
    by id_user;
run;

/* ============================================================
   5) qualitative vars -> dummy matrix -> pca -> discriminant
   (works reliably in sas 9.4; replaces mca that requires symmetric table)
   ============================================================ */

/* 5.1 base for qualitative analysis */
data mca_base;
    set clusters_full;
    if cmiss(gender, age, occupation, educationlevel, platform, freq, spend, device) > 0 then delete;
    rownum = _n_;
    keep rownum id_user cluster gender age occupation educationlevel platform freq spend device;
run;

/* 5.2 build dummy/indicator matrix */
proc glmmod data=mca_base outdesign=mca_design noprint;
    class gender age occupation educationlevel platform freq spend device;
    model cluster = gender age occupation educationlevel platform freq spend device / noint;
run;

/* add rownum + cluster back (glmmod may drop id variables) */
data mca_design;
    merge mca_design(in=a)
          mca_base(keep=rownum id_user cluster);
    if a;
run;

/* collect dummy variable names */
proc contents data=mca_design out=_varinfo(keep=name type) noprint; run;

proc sql noprint;
    select name into :dummy_vars separated by ' '
    from _varinfo
    where type=1 and upcase(name) not in ('ROWNUM','ID_USER','CLUSTER');
quit;

/* 5.3 pca on dummy matrix -> 3 dimensions (acts like mca dimensions) */
proc standard data=mca_design mean=0 std=1 out=mca_std;
    var &dummy_vars;
run;

proc princomp data=mca_std out=mca_dims n=3;
    var &dummy_vars;
run;

/* keep only the first 3 components + ids */
data final_mca;
    set mca_dims;
    keep id_user cluster prin1 prin2 prin3;
run;

/* checks */
proc sql;
select count(*) as n_final_mca from final_mca;
quit;

proc freq data=final_mca;
    tables cluster;
run;

/* 5.4 discriminant analysis using these dimensions */
proc discrim data=final_mca method=normal crossvalidate;
    class cluster;
    var prin1 prin2 prin3;
run;




/* ============================================================
   6) profiling after discriminant (as requested)
   ============================================================ */

/* anova */
proc anova data=clusters_full;
    class cluster;
    model q1 q2 q3 q4 q5 q6 = cluster;
run;
quit;

/* cluster profiles */
proc means data=clusters_full mean;
    class cluster;
    var q1-q6;
run;

/* chi-square tests */
proc freq data=clusters_full;
    tables cluster*age            / chisq;
    tables cluster*gender         / chisq;
    tables cluster*educationlevel / chisq;
    tables cluster*occupation     / chisq;
run;

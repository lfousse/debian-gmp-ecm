/* contributed by tom at womack dot net */

/* things that were consistent */
#define SPV_NTT_GFP_DIT_RECURSIVE_THRESHOLD 131072
#define PREREVERTDIVISION_NTT_THRESHOLD 16
#define POLYINVERT_NTT_THRESHOLD 256
#define POLYEVALT_NTT_THRESHOLD 256
#define MUL_NTT_THRESHOLD 256

/* things that are not granular (round to 250/500 ?) */
#define MPZMOD_THRESHOLD 249 /* range 231-264 */
#define REDC_THRESHOLD 506   /* range 505-509 */

/* things that broke 2-3 */
/* this came out as 256 twice */
#define MPZSPV_NORMALISE_STRIDE 128
/* this came out as 2048 twice */
#define SPV_NTT_GFP_DIF_RECURSIVE_THRESHOLD 4096

/* the table (individual modes) */
#define MPN_MUL_LO_THRESHOLD_TABLE {0,0,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1}

#define  PHYSICS                        HD
#define  DIMENSIONS                     3
#define  GEOMETRY                       CARTESIAN
#define  BODY_FORCE                     POTENTIAL
#define  COOLING                        NO
#define  RECONSTRUCTION                 LINEAR
#define  TIME_STEPPING                  RK2
#define  NTRACER                        0
#define  PARTICLES                      NO
#define  USER_DEF_PARAMETERS            9

/* -- physics dependent declarations -- */

#define  DUST_FLUID                     NO
#define  EOS                            IDEAL
#define  ENTROPY_SWITCH                 NO
#define  INCLUDE_LES                    NO
#define  THERMAL_CONDUCTION             NO
#define  VISCOSITY                      NO
#define  RADIATION                      NO
#define  ROTATING_FRAME                 NO

/* -- user-defined parameters (labels) -- */

#define  GAMMA                          0
#define  RHO0                           1
#define  CS0                            2
#define  MACH                           3
#define  MPERT                          4
#define  RSOFT                          5
#define  X1P                            6
#define  X2P                            7
#define  X3P                            8

/* [Beg] user-defined constants (do not change this line) */


/* [End] user-defined constants (do not change this line) */

/* ///////////////////////////////////////////////////////////////////// */
/*!
  \file
  \brief 3D Cartesian inflow past a softened point mass.
*/
/* ///////////////////////////////////////////////////////////////////// */
#include "pluto.h"
#include <sys/stat.h>

static void EnsureLogDir(void)
{
  mkdir("logs", 0775);
}

static void SetAmbientState(double *v)
{
  const double rho0 = g_inputParam[RHO0];
  const double cs0 = g_inputParam[CS0];
  const double mach = g_inputParam[MACH];

  g_gamma = g_inputParam[GAMMA];

  v[RHO] = rho0;
  v[VX1] = mach*cs0;
  v[VX2] = 0.0;
  v[VX3] = 0.0;
#if HAVE_ENERGY
  v[PRS] = rho0*cs0*cs0/g_gamma;
#endif
}

typedef struct SinkStats {
  long int cells;
  double max_alpha;
  double min_rho_before;
  double min_rho_after;
  double min_prs_before;
  double min_prs_after;
  double max_speed_before;
  double max_speed_after;
} SinkStats;

static SinkStats MakeEmptySinkStats(void)
{
  SinkStats stats;

  stats.cells = 0;
  stats.max_alpha = 0.0;
  stats.min_rho_before = 1.0e99;
  stats.min_rho_after = 1.0e99;
  stats.min_prs_before = 1.0e99;
  stats.min_prs_after = 1.0e99;
  stats.max_speed_before = 0.0;
  stats.max_speed_after = 0.0;

  return stats;
}

static SinkStats ApplyCentralSink(const Data *d, Grid *grid)
{
  const double sink_radius = g_inputParam[SINK_RADIUS];
  const double sink_timescale = g_inputParam[SINK_TIMESCALE];
  const double sink_taper_power = g_inputParam[SINK_TAPER_POWER] > 0.0 ? g_inputParam[SINK_TAPER_POWER] : 2.0;
  const double rho0 = g_inputParam[RHO0];
  const double cs0 = g_inputParam[CS0];
  const double gamma = g_inputParam[GAMMA];
  const double x1p = g_inputParam[X1P];
  const double x2p = g_inputParam[X2P];
  const double x3p = g_inputParam[X3P];
  const double target_rho = rho0;
  const double target_prs = rho0*cs0*cs0/gamma;
  double alpha_time = 1.0;
  SinkStats stats = MakeEmptySinkStats();
  int i, j, k;

  if (sink_radius <= 0.0) return stats;

  if (sink_timescale > 0.0 && g_dt > 0.0) {
    alpha_time = 1.0 - exp(-g_dt/sink_timescale);
    if (alpha_time < 0.0) alpha_time = 0.0;
    if (alpha_time > 1.0) alpha_time = 1.0;
  }

  DOM_LOOP(k,j,i) {
    const double dx = grid->x[IDIR][i] - x1p;
    const double dy = grid->x[JDIR][j] - x2p;
    const double dz = grid->x[KDIR][k] - x3p;
    const double r2 = dx*dx + dy*dy + dz*dz;

    if (r2 < sink_radius*sink_radius) {
      const double r = sqrt(r2);
      const double q = 1.0 - r/sink_radius;
      const double alpha_space = pow(q, sink_taper_power);
      const double alpha = alpha_time*alpha_space;
      const double rho_before = d->Vc[RHO][k][j][i];
      const double vx1_before = d->Vc[VX1][k][j][i];
      const double vx2_before = d->Vc[VX2][k][j][i];
      const double vx3_before = d->Vc[VX3][k][j][i];
      const double speed_before = sqrt(vx1_before*vx1_before + vx2_before*vx2_before + vx3_before*vx3_before);
      double rho_after = rho_before + alpha*(target_rho - rho_before);
      double prs_before = target_prs;
      double prs_after = target_prs;
      double vx1_after = vx1_before + alpha*(0.0 - vx1_before);
      double vx2_after = vx2_before + alpha*(0.0 - vx2_before);
      double vx3_after = vx3_before + alpha*(0.0 - vx3_before);
      double speed_after;

      stats.cells++;
      if (alpha > stats.max_alpha) stats.max_alpha = alpha;
      if (rho_before < stats.min_rho_before) stats.min_rho_before = rho_before;
      if (speed_before > stats.max_speed_before) stats.max_speed_before = speed_before;
#if HAVE_ENERGY
      prs_before = d->Vc[PRS][k][j][i];
      prs_after = prs_before + alpha*(target_prs - prs_before);
      if (prs_before < stats.min_prs_before) stats.min_prs_before = prs_before;
      d->Vc[PRS][k][j][i] = prs_after;
#endif
      speed_after = sqrt(vx1_after*vx1_after + vx2_after*vx2_after + vx3_after*vx3_after);

      d->Vc[RHO][k][j][i] = rho_after;
      d->Vc[VX1][k][j][i] = vx1_after;
      d->Vc[VX2][k][j][i] = vx2_after;
      d->Vc[VX3][k][j][i] = vx3_after;

      if (rho_after < stats.min_rho_after) stats.min_rho_after = rho_after;
      if (prs_after < stats.min_prs_after) stats.min_prs_after = prs_after;
      if (speed_after > stats.max_speed_after) stats.max_speed_after = speed_after;
    }
  }

  if (stats.cells == 0) {
    stats.min_rho_before = 0.0;
    stats.min_rho_after = 0.0;
    stats.min_prs_before = 0.0;
    stats.min_prs_after = 0.0;
  }

  return stats;
}

static void WriteSinkBoundaryLog(int side, int vpos, SinkStats stats)
{
  static int header_written = 0;
  static long int call_count = 0;
  char filename[128];
  FILE *fp;

  call_count++;
  EnsureLogDir();
  snprintf(filename, sizeof(filename), "logs/sink_boundary_3d.rank%04d.dat", prank);
  fp = fopen(filename, "a");
  if (fp == NULL) {
    printLog("! SINK_BOUNDARY: could not open %s\n", filename);
    return;
  }

  if (!header_written) {
    fprintf(fp,
      "# call step t dt side vpos sink_radius sink_timescale sink_taper_power sink_cells max_alpha min_rho_before min_rho_after min_prs_before min_prs_after max_speed_before max_speed_after\n"
    );
    header_written = 1;
  }

  fprintf(fp,
    "%ld %ld %.17e %.17e %d %d %.17e %.17e %.17e %ld %.17e %.17e %.17e %.17e %.17e %.17e %.17e\n",
    call_count, g_stepNumber, g_time, g_dt, side, vpos,
    g_inputParam[SINK_RADIUS], g_inputParam[SINK_TIMESCALE],
    g_inputParam[SINK_TAPER_POWER],
    stats.cells, stats.max_alpha,
    stats.min_rho_before, stats.min_rho_after,
    stats.min_prs_before, stats.min_prs_after,
    stats.max_speed_before, stats.max_speed_after
  );
  fclose(fp);
}

void Init (double *v, double x1, double x2, double x3)
{
  SetAmbientState(v);

#if PHYSICS == MHD || PHYSICS == RMHD
  v[BX1] = 0.0;
  v[BX2] = 0.0;
  v[BX3] = 0.0;

  v[AX1] = 0.0;
  v[AX2] = 0.0;
  v[AX3] = 0.0;
#endif
}

void InitDomain (Data *d, Grid *grid)
{
}

void Analysis (const Data *d, Grid *grid)
{
  const double cs_threshold = g_inputParam[CS_ALERT_THRESHOLD];
  const int cs_every_steps = (int)g_inputParam[CS_ALERT_EVERY_STEPS];
  const double mach_threshold = g_inputParam[MACH_ALERT_THRESHOLD];
  const int mach_every_steps = (int)g_inputParam[MACH_ALERT_EVERY_STEPS];
  static long int last_cs_alert_step = -1;
  static long int last_mach_alert_step = -1;
  static int cs_header_written = 0;
  static int mach_header_written = 0;
  double min_cs = HUGE_VAL;
  double min_rho = 0.0, min_prs = 0.0;
  double min_vx1 = 0.0, min_vx2 = 0.0, min_vx3 = 0.0;
  double min_speed = 0.0, min_mach = 0.0;
  double min_x1 = 0.0, min_x2 = 0.0, min_x3 = 0.0;
  double max_mach = -HUGE_VAL;
  double max_rho = 0.0, max_prs = 0.0, max_cs = 0.0;
  double max_vx1 = 0.0, max_vx2 = 0.0, max_vx3 = 0.0;
  double max_speed = 0.0;
  double max_x1 = 0.0, max_x2 = 0.0, max_x3 = 0.0;
  int min_i = IBEG, min_j = JBEG, min_k = KBEG;
  int max_i = IBEG, max_j = JBEG, max_k = KBEG;
  int cs_invalid_state = 0;
  int mach_invalid_state = 0;
  int i, j, k;

  if (cs_threshold <= 0.0 && mach_threshold <= 0.0) return;

  DOM_LOOP(k,j,i) {
    const double rho = d->Vc[RHO][k][j][i];
    const double vx1 = d->Vc[VX1][k][j][i];
    const double vx2 = d->Vc[VX2][k][j][i];
    const double vx3 = d->Vc[VX3][k][j][i];
    const double speed = sqrt(vx1*vx1 + vx2*vx2 + vx3*vx3);
    double prs = 0.0;
    double cs = 0.0;
    double mach = HUGE_VAL;
    int bad = 0;

#if HAVE_ENERGY
    prs = d->Vc[PRS][k][j][i];
    if (rho > 0.0 && prs > 0.0) {
      cs = sqrt(g_inputParam[GAMMA]*prs/rho);
      mach = speed/cs;
    } else {
      bad = 1;
    }
#else
    prs = rho*g_inputParam[CS0]*g_inputParam[CS0];
    if (rho > 0.0) {
      cs = g_inputParam[CS0];
      mach = speed/cs;
    } else {
      bad = 1;
    }
#endif

    if (bad || cs < min_cs) {
      min_cs = cs;
      min_rho = rho;
      min_prs = prs;
      min_vx1 = vx1;
      min_vx2 = vx2;
      min_vx3 = vx3;
      min_speed = speed;
      min_mach = mach;
      min_x1 = grid->x[IDIR][i];
      min_x2 = grid->x[JDIR][j];
      min_x3 = grid->x[KDIR][k];
      min_i = i;
      min_j = j;
      min_k = k;
      cs_invalid_state = bad;
    }

    if (bad || mach > max_mach) {
      max_mach = mach;
      max_rho = rho;
      max_prs = prs;
      max_cs = cs;
      max_vx1 = vx1;
      max_vx2 = vx2;
      max_vx3 = vx3;
      max_speed = speed;
      max_x1 = grid->x[IDIR][i];
      max_x2 = grid->x[JDIR][j];
      max_x3 = grid->x[KDIR][k];
      max_i = i;
      max_j = j;
      max_k = k;
      mach_invalid_state = bad;
    }
  }

  if (cs_threshold > 0.0 && (cs_invalid_state || min_cs < cs_threshold) &&
      !(last_cs_alert_step >= 0 && cs_every_steps > 0 &&
        g_stepNumber - last_cs_alert_step < cs_every_steps)) {
    last_cs_alert_step = g_stepNumber;

    printLog(
      "! CS_ALERT step=%ld t=%12.6e dt=%12.6e min_cs=%12.6e threshold=%12.6e "
      "invalid=%d i=%d j=%d k=%d x=(%12.6e,%12.6e,%12.6e) "
      "rho=%12.6e prs=%12.6e v=(%12.6e,%12.6e,%12.6e) speed=%12.6e mach=%12.6e\n",
      g_stepNumber, g_time, g_dt, min_cs, cs_threshold, cs_invalid_state,
      min_i, min_j, min_k, min_x1, min_x2, min_x3,
      min_rho, min_prs, min_vx1, min_vx2, min_vx3, min_speed, min_mach
    );

    char filename[128];
    FILE *fp;

    EnsureLogDir();
    snprintf(filename, sizeof(filename), "logs/diagnostics_cs_alert_3d.rank%04d.dat", prank);
    fp = fopen(filename, "a");
    if (fp == NULL) {
      printLog("! CS_ALERT: could not open %s\n", filename);
    } else {
      if (!cs_header_written) {
        fprintf(fp,
          "# step t dt min_cs threshold invalid i j k x1 x2 x3 rho prs vx1 vx2 vx3 speed mach\n"
        );
        cs_header_written = 1;
      }
      fprintf(fp,
        "%ld %.17e %.17e %.17e %.17e %d %d %d %d "
        "%.17e %.17e %.17e %.17e %.17e %.17e %.17e %.17e %.17e %.17e\n",
        g_stepNumber, g_time, g_dt, min_cs, cs_threshold, cs_invalid_state,
        min_i, min_j, min_k, min_x1, min_x2, min_x3,
        min_rho, min_prs, min_vx1, min_vx2, min_vx3, min_speed, min_mach
      );
      fclose(fp);
    }
  }

  if (mach_threshold > 0.0 && (mach_invalid_state || max_mach > mach_threshold) &&
      !(last_mach_alert_step >= 0 && mach_every_steps > 0 &&
        g_stepNumber - last_mach_alert_step < mach_every_steps)) {
    char filename[128];
    FILE *fp;

    last_mach_alert_step = g_stepNumber;

    printLog(
      "! MACH_ALERT step=%ld t=%12.6e dt=%12.6e max_mach=%12.6e threshold=%12.6e "
      "invalid=%d i=%d j=%d k=%d x=(%12.6e,%12.6e,%12.6e) "
      "rho=%12.6e prs=%12.6e cs=%12.6e v=(%12.6e,%12.6e,%12.6e) speed=%12.6e\n",
      g_stepNumber, g_time, g_dt, max_mach, mach_threshold, mach_invalid_state,
      max_i, max_j, max_k, max_x1, max_x2, max_x3,
      max_rho, max_prs, max_cs, max_vx1, max_vx2, max_vx3, max_speed
    );

    EnsureLogDir();
    snprintf(filename, sizeof(filename), "logs/diagnostics_mach_alert_3d.rank%04d.dat", prank);
    fp = fopen(filename, "a");
    if (fp == NULL) {
      printLog("! MACH_ALERT: could not open %s\n", filename);
    } else {
      if (!mach_header_written) {
        fprintf(fp,
          "# step t dt max_mach threshold invalid i j k x1 x2 x3 rho prs cs vx1 vx2 vx3 speed\n"
        );
        mach_header_written = 1;
      }
      fprintf(fp,
        "%ld %.17e %.17e %.17e %.17e %d %d %d %d "
        "%.17e %.17e %.17e %.17e %.17e %.17e %.17e %.17e %.17e %.17e\n",
        g_stepNumber, g_time, g_dt, max_mach, mach_threshold, mach_invalid_state,
        max_i, max_j, max_k, max_x1, max_x2, max_x3,
        max_rho, max_prs, max_cs, max_vx1, max_vx2, max_vx3, max_speed
      );
      fclose(fp);
    }
  }
}

#if PHYSICS == MHD
void BackgroundField (double x1, double x2, double x3, double *B0)
{
   B0[0] = 0.0;
   B0[1] = 0.0;
   B0[2] = 0.0;
}
#endif

void UserDefBoundary (const Data *d, RBox *box, int side, Grid *grid)
{
  int   i, j, k, nv;

  if (side == 0) {
    SinkStats sink_stats = ApplyCentralSink(d, grid);
    WriteSinkBoundaryLog(side, box == NULL ? -1 : box->vpos, sink_stats);
  }

  if (side == X1_BEG){
    if (box->vpos == CENTER) {
      BOX_LOOP(box,k,j,i){
        double v_amb[NVAR];

        SetAmbientState(v_amb);
        NVAR_LOOP(nv) d->Vc[nv][k][j][i] = v_amb[nv];
      }
    }else if (box->vpos == X1FACE){
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X2FACE){
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X3FACE){
      BOX_LOOP(box,k,j,i){  }
    }
  }

  if (side == X1_END){
    if (box->vpos == CENTER) {
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X1FACE){
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X2FACE){
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X3FACE){
      BOX_LOOP(box,k,j,i){  }
    }
  }

  if (side == X2_BEG){
    if (box->vpos == CENTER) {
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X1FACE){
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X2FACE){
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X3FACE){
      BOX_LOOP(box,k,j,i){  }
    }
  }

  if (side == X2_END){
    if (box->vpos == CENTER) {
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X1FACE){
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X2FACE){
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X3FACE){
      BOX_LOOP(box,k,j,i){  }
    }
  }

  if (side == X3_BEG){
    if (box->vpos == CENTER) {
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X1FACE){
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X2FACE){
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X3FACE){
      BOX_LOOP(box,k,j,i){  }
    }
  }

  if (side == X3_END){
    if (box->vpos == CENTER) {
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X1FACE){
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X2FACE){
      BOX_LOOP(box,k,j,i){  }
    }else if (box->vpos == X3FACE){
      BOX_LOOP(box,k,j,i){  }
    }
  }
}

#if BODY_FORCE != NO
void BodyForceVector(double *v, double *g, double x1, double x2, double x3)
{
  const double mp = g_inputParam[MPERT];
  const double rs = g_inputParam[RSOFT];
  const double x1p = g_inputParam[X1P];
  const double x2p = g_inputParam[X2P];
  const double x3p = g_inputParam[X3P];
  const double dx = x1 - x1p;
  const double dy = x2 - x2p;
  const double dz = x3 - x3p;
  const double r2 = dx*dx + dy*dy + dz*dz + rs*rs;
  const double inv_r3 = 1.0/(r2*sqrt(r2));

  g[IDIR] = -mp*dx*inv_r3;
  g[JDIR] = -mp*dy*inv_r3;
  g[KDIR] = -mp*dz*inv_r3;
}

double BodyForcePotential(double x1, double x2, double x3)
{
  const double mp = g_inputParam[MPERT];
  const double rs = g_inputParam[RSOFT];
  const double x1p = g_inputParam[X1P];
  const double x2p = g_inputParam[X2P];
  const double x3p = g_inputParam[X3P];
  const double dx = x1 - x1p;
  const double dy = x2 - x2p;
  const double dz = x3 - x3p;
  const double r2 = dx*dx + dy*dy + dz*dz + rs*rs;

  return -mp/sqrt(r2);
}
#endif

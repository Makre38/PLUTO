/* ///////////////////////////////////////////////////////////////////// */
/*!
  \file
  \brief 3D Cartesian inflow past a softened point mass.
*/
/* ///////////////////////////////////////////////////////////////////// */
#include "pluto.h"

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
    DOM_LOOP(k,j,i){}
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

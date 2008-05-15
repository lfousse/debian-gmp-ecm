/* Dickman's rho function (to compute probability of success of ecm).

  Copyright 2004, 2005 Alexander Kruppa.

  This file is part of the ECM Library.

  The ECM Library is free software; you can redistribute it and/or modify
  it under the terms of the GNU Lesser General Public License as published by
  the Free Software Foundation; either version 2.1 of the License, or (at your
  option) any later version.

  The ECM Library is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
  or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
  License for more details.

  You should have received a copy of the GNU Lesser General Public License
  along with the ECM Library; see the file COPYING.LIB.  If not, write to
  the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
  MA 02110-1301, USA.
*/

#if defined(DEBUG_NUMINTEGRATE) || defined(TESTDRIVE)
# include <stdio.h>
#endif
#include <stdlib.h>
#include <math.h>
#include "ecm-impl.h"

#ifndef ECM_EXTRA_SMOOTHNESS
#define ECM_EXTRA_SMOOTHNESS 23.4
#endif

#define M_PI_SQR   9.869604401089358619 /* Pi^2 */
#define M_PI_SQR_6 1.644934066848226436 /* Pi^2/6 */
#define M_EULER    0.577215664901532861
#define M_EULER_1   0.422784335098467139 /* 1 - Euler */

void rhoinit (int, int); /* used in stage2.c */

static double *rhotable = NULL;
static int invh = 0;
static double h = 0.;
static int tablemax = 0;

#ifdef TESTDRIVE
static unsigned int
gcd (unsigned int a, unsigned int b)
{
  unsigned int t;

  while (b != 0)
    {
      t = a % b;
      a = b;
      b = t;
    }

  return a;
}

static unsigned long
eulerphi (unsigned long n)
{
  unsigned long phi = 1, p;

  for (p = 2; p * p <= n; p += 2)
    {
      if (n % p == 0)
        {
          phi *= p - 1;
          n /= p;
          while (n % p == 0)
            {
              phi *= p;
              n /= p;
            }
        }

      if (p == 2)
        p--;
    }

  /* now n is prime */

  return (n == 1) ? phi : phi * (n - 1);
}
#endif /* TESTDRIVE */

/*
  Evaluate dilogarithm via the sum 
  \Li_{2}(z)=\sum_{k=1}^{\infty} \frac{z^k}{k^2}, 
  see http://mathworld.wolfram.com/Dilogarithm.html
  Assumes |z| <= 0.5, for which the sum converges quickly.
 */

static double
dilog_series (const double z)
{
  double r = 0.0, zk; /* zk = z^k */
  int k, k2; /* k2 = k^2 */
  /* Doubles have 53 bits in significand, with |z| <= 0.5 the k+1-st term
     is <= 1/(2^k k^2) of the result, so 44 terms should do */
  for (k = 1, k2 = 1, zk = z; k <= 44; k2 += 2 * k + 1, k++, zk *= z)
    r += zk / (double) k2;

  return r;
}

static double
dilog (double x)
{
  ASSERT(x <= -1.0); /* dilog(1-x) is called from rhoexact for 2 < x <= 3 */

  if (x <= -2.0)
    return -dilog_series (1./x) - M_PI_SQR_6 - 0.5 * log(-1./x) * log(-1./x);
  else /* x <= -1.0 */
    {
      /* L2(z) = -L2(1 - z) + 1/6 * Pi^2 - ln(1 - z)*ln(z) 
         L2(z) = -L2(1/z) - 1/6 * Pi^2 - 0.5*ln^2(-1/z)
         ->
         L2(z) = -(-L2(1/(1-z)) - 1/6 * Pi^2 - 0.5*ln^2(-1/(1-z))) + 1/6 * Pi^2 - ln(1 - z)*ln(z)
               = L2(1/(1-z)) - 1/6 * Pi^2 + 0.5*ln(1 - z)^2 - ln(1 - z)*ln(-z)
         z in [-1, -2) -> 1/(1-z) in [1/2, 1/3)
      */
      double log1x = log (1. - x);
      return dilog_series (1. / (1. - x)) 
             - M_PI_SQR_6 + log1x * (0.5 * log1x - log (-x));
    }
}

#if 0
static double 
L2 (double x)
{
  return log (x) * (1 - log (x-1)) + M_PI_SQR_6 - dilog (1 - x);
}
#endif

static double
rhoexact (double x)
{
  ASSERT(x <= 3.);
  if (x <= 0.)
    return 0.;
  if (x <= 1.)
    return 1.;
  if (x <= 2.)
    return 1. - log (x);
  if (x <= 3.) /* 2 < x <= 3 thus -2 <= 1-x < -1 */
    return 1. - log (x) * (1. - log (x - 1.)) + dilog (1. - x) + 0.5 * M_PI_SQR_6;
  
  return 0.; /* x > 3. and asserting not enabled: bail out with 0. */
}

void 
rhoinit (int parm_invh, int parm_tablemax)
{
  int i;

  if (parm_invh == invh && parm_tablemax == tablemax)
    return;

  if (rhotable != NULL)
    {
      free (rhotable);
      rhotable = NULL;
      invh = 0;
      h = 0.;
      tablemax = 0;
    }
  
  /* The integration below expects 3 * invh > 4 */
  if (parm_tablemax == 0 || parm_invh < 2)
    return;
    
  invh = parm_invh;
  h = 1. / (double) invh;
  tablemax = parm_tablemax;
  
  rhotable = (double *) malloc (parm_invh * parm_tablemax * sizeof (double));
  
  for (i = 0; i < (3 < parm_tablemax ? 3 : parm_tablemax) * invh; i++)
    rhotable[i] = rhoexact (i * h);
  
  for (i = 3 * invh; i < parm_tablemax * invh; i++)
    {
      /* rho(i*h) = 1 - \int_{1}^{i*h} rho(x-1)/x dx
                  = rho((i-4)*h) - \int_{(i-4)*h}^{i*h} rho(x-1)/x dx */
      
      rhotable[i] = rhotable[i - 4] - 2. / 45. * (
          7. * rhotable[i - invh - 4] / (double)(i - 4)
        + 32. * rhotable[i - invh - 3] / (double)(i - 3)
        + 12. * rhotable[i - invh - 2] / (double)(i - 2)
        + 32. * rhotable[i - invh - 1] / (double)(i - 1)
        + 7. * rhotable[i - invh]  / (double)i );
      if (rhotable[i] < 0.)
        {
#ifndef DEBUG_NUMINTEGRATE
          rhotable[i] = 0.;
#else
          printf (stderr, "rhoinit: rhotable[%d] = %.16f\n", i, 
                   rhotable[i]);
          exit (EXIT_FAILURE);
#endif
        }
    }
}

static double
dickmanrho (double alpha)
{
  if (alpha <= 3.)
     return rhoexact (alpha);
  if (alpha < tablemax)
    {
      int a = floor (alpha * invh);
      double rho1 = rhotable[a];
      double rho2 = (a + 1) < tablemax * invh ? rhotable[a + 1] : 0;
      return rho1 + (rho2 - rho1) * (alpha * invh - (double)a);
    }
  
  return 0.;
}

static double 
dickmanrhosigma (double alpha, double x)
{
  if (alpha <= 0.)
    return 0.;
  if (alpha <= 1.)
    return 1.;
  if (alpha < tablemax)
    return dickmanrho (alpha) + M_EULER_1 * dickmanrho (alpha - 1.) / log (x);
  
  return 0.;
}

#if 0
static double
dickmanrhosigma_i (int ai, double x)
{
  if (ai <= 0)
    return 0.;
  if (ai <= invh)
    return 1.;
  if (ai < tablemax * invh)
    return rhotable[ai] - M_EULER * rhotable[ai - invh] / log(x);
  
  return 0.;
}
#endif

static double
dickmanlocal (double alpha, double x)
{
  if (alpha <= 0.)
    return 0.;
  if (alpha <= 1.)
    return 1.;
  if (alpha < tablemax)
    return dickmanrhosigma (alpha, x) 
           - dickmanrhosigma (alpha - 1., x) / log (x);
  return 0.;
}

static double
dickmanlocal_i (int ai, double x)
{
  if (ai <= 0)
    return 0.;
  if (ai <= invh)
    return 1.;
  if (ai <= 2 * invh && ai < tablemax * invh)
    return rhotable[ai] - M_EULER / log (x);
  if (ai < tablemax * invh)
    {
      double logx = log (x);
      return rhotable[ai] - (M_EULER * rhotable[ai - invh]
             + M_EULER_1 * rhotable[ai - 2 * invh] / logx) / logx;
    }

  return 0.;
}

static double
dickmanmu (double alpha, double beta, double x)
{
  double a, b, sum;
  int ai, bi, i;
  ai = ceil ((alpha - beta) * invh);
  if (ai > tablemax * invh)
    ai = tablemax * invh;
  a = (double) ai * h;
  bi = floor ((alpha - 1.) * invh);
  if (bi > tablemax * invh)
    bi = tablemax * invh;
  b = (double) bi * h;
  sum = 0.;
  for (i = ai + 1; i < bi; i++)
    sum += dickmanlocal_i (i, x) / (alpha - i * h);
  sum += 0.5 * dickmanlocal_i (ai, x) / (alpha - a);
  sum += 0.5 * dickmanlocal_i (bi, x) / (alpha - b);
  sum *= h;
  sum += (a - alpha + beta) * 0.5 * (dickmanlocal_i (ai, x) / (alpha - a) + dickmanlocal (alpha - beta, x) / beta);
  sum += (alpha - 1. - b) * 0.5 * (dickmanlocal (alpha - 1., x) + dickmanlocal_i (bi, x) / (alpha - b));

  return sum;
}

static double
brentsuyama (double B1, double B2, double N, double nr)
{
  double a, alpha, beta, sum;
  int ai, i;
  alpha = log (N) / log (B1);
  beta = log (B2) / log (B1);
  ai = floor ((alpha - beta) * invh);
  if (ai > tablemax * invh)
    ai = tablemax * invh;
  a = (double) ai * h;
  sum = 0.;
  for (i = 1; i < ai; i++)
    sum += dickmanlocal_i (i, N) / (alpha - i * h) * (1 - exp (-nr * pow (B1, (-alpha + i * h))));
  sum += 0.5 * (1 - exp(-nr / pow (B1, alpha)));
  sum += 0.5 * dickmanlocal_i (ai, N) / (alpha - a) * (1 - exp(-nr * pow (B1, (-alpha + a))));
  sum *= h;
  sum += 0.5 * (alpha - beta - a) * (dickmanlocal_i (ai, N) / (alpha - a) + dickmanlocal (alpha - beta, N) / beta);

  return sum;
}

static double 
brsudickson (double B1, double B2, double N, double nr, int S)
{
  int i, f;
  double sum;
  sum = 0;
  f = eulerphi (S) / 2;
  for (i = 1; i <= S / 2; i++)
      if (gcd (i, S) == 1)
        sum += brentsuyama (B1, B2, N, nr * (gcd (i - 1, S) + gcd (i + 1, S) - 4) / 2);
  
  return sum / (double)f;
}

static double
brsupower (double B1, double B2, double N, double nr, int S)
{
  int i, f;
  double sum;
  sum = 0;
  f = eulerphi (S);
  for (i = 1; i < S; i++)
      if (gcd (i, S) == 1)
        sum += brentsuyama (B1, B2, N, nr * (gcd (i - 1, S) - 2));
  
  return sum / (double)f;
}

double
ecmprob (double B1, double B2, double N, double nr, int S)
{
  double alpha, beta, stage1, stage2, brsu;

  ASSERT(rhotable != NULL);
  
  /* What to do if rhotable is not initialised and asserting is not enabled?
     For now, bail out with 0. result. Not really pretty, either */
  if (rhotable == NULL)
    return 0.;

  if (B1 < 2. || N <= 1.)
    return 0.;
  
  if (N / ECM_EXTRA_SMOOTHNESS <= B1)
    return 1.;

#ifdef TESTDRIVE
  printf ("B1 = %f, B2 = %f, N = %.0f, nr = %f, S = %d\n", B1, B2, N, nr, S);
#endif
  
  alpha = log (N / ECM_EXTRA_SMOOTHNESS) / log (B1);
  stage1 = dickmanlocal (alpha, N / ECM_EXTRA_SMOOTHNESS);
  stage2 = 0.;
  if (B2 > B1)
    {
      beta = log (B2) / log (B1);
      stage2 = dickmanmu (alpha, beta, N / ECM_EXTRA_SMOOTHNESS);
    }
  brsu = 0.;
  if (S < -1)
    brsu = brsudickson (B1, B2, N / ECM_EXTRA_SMOOTHNESS, nr, -S * 2);
  if (S > 1)
    brsu = brsupower (B1, B2, N / ECM_EXTRA_SMOOTHNESS, nr, S * 2);

#ifdef TESTDRIVE
  printf ("stage 1 : %f, stage 2 : %f, Brent-Suyama : %f\n", stage1, stage2, brsu);
#endif

  return (stage1 + stage2 + brsu) > 0. ? (stage1 + stage2 + brsu) : 0.;
}

#ifdef TESTDRIVE
int
main (int argc, char **argv)
{
  double B1, B2, N, nr;
  int S;
  if (argc < 6)
    return 1;
  
  B1 = atof (argv[1]);
  B2 = atof (argv[2]);
  N = atof (argv[3]);
  nr = atof (argv[4]);
  S = atoi (argv[5]);
  rhoinit (256, 10);
  printf ("%.16f\n", ecmprob(B1, B2, N, nr, S));
  return 0;
}
#endif

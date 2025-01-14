/*
Copyright (c) 2013-2021 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

/**
 * Linear equation system solvers
 *
 * Description:
 * A system is given in matrix form: 
 * ---
 * Ax = b
 * ---
 * For example:
 * ---
 * x + 3y - 2z = 5
 * 3x + 5y + 6z = 7
 * 2x + 4y + 3z = 8 
 * ---
 * For this system, A (coefficient matrix) will be
 * ---
 * [1, 3, -2]
 * [3, 5,  6]
 * [2, 4,  3]
 * ---
 * And b (right side vector) will be 
 * ---
 * [5, 7, 8]
 * ---
 * x is a vector of unknowns:
 * ---
 * [x, y, z]
 * ---
 *
 * Copyright: Timur Gafarov 2013-2021.
 * License: $(LINK2 boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Timur Gafarov
 */
module dlib.math.linsolve;

import dlib.math.matrix;
import dlib.math.vector;
import dlib.math.decomposition;

// TODO: use arrays instead of Matrix structs to support big systems stored in heap

/// Solve Ax = b iteratively using Gauss-Seidel method
void solveGS(T, size_t N)(
      Matrix!(T,N) a,
  ref Vector!(T,N) x,
      Vector!(T,N) b,
      uint iterations = 10)
{
    double delta;

    for (int k = 0; k < iterations; ++k)
    {
        for (int i = 0; i < N; ++i)
        {
            delta = 0.0;

            for (int j = 0; j < i; ++j)
                delta += a[j, i] * x[j];

            for (int j = i + 1; j < N; ++j)
                delta += a[j, i] * x[j];

            delta = (b[i] - delta) / a[i, i];
            x[i] = delta;
        }
    }
}

/// Solve Ax = b directly using LUP decomposition
void solve(T, size_t N)(
      Matrix!(T,N) a,
  ref Vector!(T,N) x,
      Vector!(T,N) b)
{
    Matrix!(T,N) L, U, P;
    decomposeLUP(a, L, U, P);
    solveLU(L, U, x, b * P);
}

/// Solve LUx = b directly
void solveLU(T, size_t N)(
    Matrix!(T,N) L,
    Matrix!(T,N) U,
ref Vector!(T,N) x,
    Vector!(T,N) b)
{
    int i = 0;
    int j = 0;
    Vector!(T,N) y;

    // Forward solve Ly = b
    for (i = 0; i < N; i++)
    {
        y[i] = b[i];
        for (j = 0; j < i; j++)
            y[i] -= L[i, j] * y[j];
        y[i] /= L[i, i];
    }

    // Backward solve Ux = y
    for (i = N - 1; i >= 0; i--)
    {
        x[i] = y[i];
        for (j = i + 1; j < N; j++)
            x[i] -= U[i, j] * x[j];
        x[i] /= U[i, i];
    }
}

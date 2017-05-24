/*
Copyright (c) 2013-2017 Timur Gafarov

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

module dlib.geometry.trimesh;

private
{
    import std.stdio;
    import std.math;
    import dlib.math.vector;
    import dlib.geometry.triangle;
}

struct TriMesh
{
    Vector3f[] vertices;
    Vector3f[] normals;
    Vector4f[] tangents;
    Vector2f[] texcoords1;
    Vector2f[] texcoords2;
    uint numTexCoords = 0;

    struct Index
    {
        uint a, b, c;
    }

    struct FaceGroup
    {
        Index[] indices;
        int materialIndex;
    }

    FaceGroup[] facegroups;

    Triangle getTriangle(uint facegroupIndex, uint triIndex)
    {
        Triangle tri;
        Index triIdx = facegroups[facegroupIndex].indices[triIndex];

        tri.v[0] = vertices[triIdx.a];
        tri.v[1] = vertices[triIdx.b];
        tri.v[2] = vertices[triIdx.c];

        tri.n[0] = normals[triIdx.a];
        tri.n[1] = normals[triIdx.b];
        tri.n[2] = normals[triIdx.c];

        if (numTexCoords > 0)
        {
            tri.t1[0] = texcoords1[triIdx.a];
            tri.t1[1] = texcoords1[triIdx.b];
            tri.t1[2] = texcoords1[triIdx.c];

            if (numTexCoords > 1)
            {
                tri.t2[0] = texcoords2[triIdx.a];
                tri.t2[1] = texcoords2[triIdx.b];
                tri.t2[2] = texcoords2[triIdx.c];
            }
        }

        tri.normal = planeNormal(tri.v[0], tri.v[1], tri.v[2]);

        tri.barycenter = (tri.v[0] + tri.v[1] + tri.v[2]) / 3;

        tri.d = (tri.v[0].x * tri.normal.x +
                 tri.v[0].y * tri.normal.y +
                 tri.v[0].z * tri.normal.z);

        tri.edges[0] = tri.v[1] - tri.v[0];
        tri.edges[1] = tri.v[2] - tri.v[1];
        tri.edges[2] = tri.v[0] - tri.v[2];

        tri.materialIndex = facegroups[facegroupIndex].materialIndex;

        return tri;
    }

    // Read-only triangle aggregate:
    // foreach(tri; mesh) ...
    int opApply(scope int delegate(ref Triangle) dg)
    {
        int result = 0;
        for (uint fgi = 0; fgi < facegroups.length; fgi++)
        for (uint i = 0; i < facegroups[fgi].indices.length; i++)
        {
            Triangle tri = getTriangle(fgi, i);
            result = dg(tri);
            if (result)
                break;
        }
        return result;
    }

    void genTangents()
    {
        Vector3f[] sTan = new Vector3f[vertices.length];
        Vector3f[] tTan = new Vector3f[vertices.length];

        foreach(i, v; sTan)
        {
            sTan[i] = Vector3f(0.0f, 0.0f, 0.0f);
            tTan[i] = Vector3f(0.0f, 0.0f, 0.0f);
        }

        foreach(ref fg; facegroups)
        foreach(ref index; fg.indices)
        {
            uint i0 = index.a;
            uint i1 = index.b;
            uint i2 = index.c;

            Vector3f v0 = vertices[i0];
            Vector3f v1 = vertices[i1];
            Vector3f v2 = vertices[i2];

            Vector2f w0 = texcoords1[i0];
            Vector2f w1 = texcoords1[i1];
            Vector2f w2 = texcoords1[i2];

            float x1 = v1.x - v0.x;
            float x2 = v2.x - v0.x;
            float y1 = v1.y - v0.y;
            float y2 = v2.y - v0.y;
            float z1 = v1.z - v0.z;
            float z2 = v2.z - v0.z;

            float s1 = w1[0] - w0[0];
            float s2 = w2[0] - w0[0];
            float t1 = w1[1] - w0[1];
            float t2 = w2[1] - w0[1];

            float r = (s1 * t2) - (s2 * t1);

            // Prevent division by zero
            if (r == 0.0f)
                r = 1.0f;

            float oneOverR = 1.0f / r;

            Vector3f sDir = Vector3f((t2 * x1 - t1 * x2) * oneOverR,
                                     (t2 * y1 - t1 * y2) * oneOverR,
                                     (t2 * z1 - t1 * z2) * oneOverR);
            Vector3f tDir = Vector3f((s1 * x2 - s2 * x1) * oneOverR,
                                     (s1 * y2 - s2 * y1) * oneOverR,
                                     (s1 * z2 - s2 * z1) * oneOverR);

            sTan[i0] += sDir;
            tTan[i0] += tDir;

            sTan[i1] += sDir;
            tTan[i1] += tDir;

            sTan[i2] += sDir;
            tTan[i2] += tDir;
        }

        tangents = new Vector4f[vertices.length];

        // Calculate vertex tangent
        foreach(i, v; tangents)
        {
            Vector3f n = normals[i];
            Vector3f t = sTan[i];

            // Gram-Schmidt orthogonalize
            Vector3f tangent = (t - n * dot(n, t));
            tangent.normalize();

            tangents[i].x = tangent.x;
            tangents[i].y = tangent.y;
            tangents[i].z = tangent.z;

            // Calculate handedness
            if (dot(cross(n, t), tTan[i]) < 0.0f)
                tangents[i].w = -1.0f;
            else
                tangents[i].w = 1.0f;
        }
    }
}
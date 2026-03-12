#include "LightingUtil.hlsl"

Texture2D InputTexture : register(t0);

cbuffer cbPass : register(b0)
{
    float4x4 gView;
    float4x4 gInvView;
    float4x4 gProj;
    float4x4 gInvProj;
    float4x4 gViewProj;
    float4x4 gInvViewProj;
    float3 gEyePosW;
    float cbPerObjectPad1;
    float2 gRenderTargetSize;
    float2 gInvRenderTargetSize;
    float gNearZ;
    float gFarZ;
    float gTotalTime;
    float gDeltaTime;
};

cbuffer LightConstants : register(b1)
{
    Light light;
    float3 LColor;
    int LightType; //0 - directional; 1 - point; 2 - spot
    float4x4 LWorld;
    float4x4 LViewProj[6];
    float4x4 LShadowTransform[6];
};

struct VertexOut
{
    float4 PosH : SV_Position;
};

struct psout
{
    float depth : SV_Depth;
};

VertexOut VS(uint vertexID : SV_VertexID)
{
    float2 verts[3] =
    {
        float2(-1, -1),
        float2(-1, 3),
        float2(3, -1)
    };

    VertexOut vo;
    vo.PosH = float4(verts[vertexID], 0, 1);
    return vo;
}

psout PS(VertexOut pin)
{
    psout res;

    int2 center = int2(pin.PosH.xy);

    const int kernelRadius = 20;
    const float sigma = kernelRadius / 2.5f;

    float blurredDepth = 0.0f;
    float weightSum = 0.0f;

#if defined(BLUR_HORIZONTAL)
    int2 axis = int2(1, 0);
#else
    int2 axis = int2(0, 1);
#endif

    [loop]
    for (int i = -kernelRadius; i <= kernelRadius; i++)
    {
        int2 samplePos = center + axis * i;

        if (samplePos.x < 0 || samplePos.y < 0 ||
            samplePos.x >= (int) gRenderTargetSize.x ||
            samplePos.y >= (int) gRenderTargetSize.y)
            continue;

        float depthSample = InputTexture.Load(int3(samplePos, 0)).x;

        float dist2 = float(i * i);
        float weight = exp(-dist2 / (2.0f * sigma * sigma));

        blurredDepth += depthSample * weight;
        weightSum += weight;
    }

    res.depth = (weightSum > 0.0f) ? (blurredDepth / weightSum)
                                   : InputTexture.Load(int3(center, 0)).x;

    return res;
}
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4"

const B2_KEY_ID = Deno.env.get("B2_KEY_ID") || ""
const B2_MASTER_KEY = Deno.env.get("B2_MASTER_KEY") || ""
const B2_BUCKET_NAME = Deno.env.get("B2_BUCKET_NAME") || "attendance-students-photos"
const B2_BUCKET_ID = Deno.env.get("B2_BUCKET_ID") || ""

interface UploadRequest {
  fileName: string
  folder: string
  contentType: string
  fileBuffer: string // base64
}

// B2 Authorization
async function authorizeB2() {
  const credentials = `${B2_KEY_ID}:${B2_MASTER_KEY}`
  const encoded = btoa(credentials)

  const response = await fetch("https://api.backblazeb2.com/b2api/v2/b2_authorize_account", {
    method: "POST",
    headers: {
      Authorization: `Basic ${encoded}`,
    },
  })

  if (!response.ok) {
    throw new Error(`B2 authorization failed: ${response.statusText}`)
  }

  const auth = await response.json()
  return {
    authorizationToken: auth.authorizationToken,
    apiUrl: auth.apiUrl,
    downloadUrl: auth.downloadUrl,
  }
}

// Get B2 upload URL
async function getB2UploadUrl(auth: any) {
  const response = await fetch(`${auth.apiUrl}/b2api/v2/b2_get_upload_url`, {
    method: "POST",
    headers: {
      Authorization: auth.authorizationToken,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ bucketId: B2_BUCKET_ID }),
  })

  if (!response.ok) {
    throw new Error(`Failed to get B2 upload URL: ${response.statusText}`)
  }

  return await response.json()
}

// Upload to B2
async function uploadToB2(uploadUrl: any, fileBuffer: Uint8Array, fileName: string, contentType: string) {
  const sha1 = await crypto.subtle.digest("SHA-1", fileBuffer)
  const sha1Hex = Array.from(new Uint8Array(sha1))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")

  const response = await fetch(uploadUrl.uploadUrl, {
    method: "POST",
    headers: {
      Authorization: uploadUrl.authorizationToken,
      "X-Bz-File-Name": encodeURIComponent(fileName),
      "Content-Type": contentType,
      "X-Bz-Content-Sha1": sha1Hex,
    },
    body: fileBuffer,
  })

  if (!response.ok) {
    throw new Error(`B2 upload failed: ${response.statusText}`)
  }

  return await response.json()
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Max-Age": "86400",
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: {
        "Content-Type": "application/json",
        ...corsHeaders,
      },
    })
  }

  try {
    // Verify JWT token
    const authHeader = req.headers.get("Authorization") || ""
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : ""

    if (!token) {
      return new Response(JSON.stringify({ error: "Missing authorization token" }), {
        status: 401,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      })
    }

    // Parse request body
    const body = await req.json() as UploadRequest
    const { fileName, folder, contentType, fileBuffer } = body

    if (!fileName || !fileBuffer) {
      return new Response(JSON.stringify({ error: "Missing file data" }), {
        status: 400,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      })
    }

    // Decode base64 file
    const binaryString = atob(fileBuffer)
    const bytes = new Uint8Array(binaryString.length)
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i)
    }

    // Upload to B2
    const auth = await authorizeB2()
    const uploadUrl = await getB2UploadUrl(auth)
    const fullFileName = `${folder}${fileName}`
    const uploadResult = await uploadToB2(uploadUrl, bytes, fullFileName, contentType)

    const publicUrl = `${auth.downloadUrl}/file/${encodeURIComponent(B2_BUCKET_NAME)}/${encodeURIComponent(fullFileName)}`

    return new Response(
      JSON.stringify({
        success: true,
        fileName: uploadResult.fileName,
        fileId: uploadResult.fileId,
        publicUrl,
        downloadUrl: publicUrl,
      }),
      {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
      }
    )
  } catch (error) {
    console.error("Upload error:", error)
    return new Response(
      JSON.stringify({ error: error.message || "Upload failed" }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
      }
    )
  }
})

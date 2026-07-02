import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { encodeBase64 } from "https://deno.land/std@0.168.0/encoding/base64.ts"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
}

const B2_KEY_ID = Deno.env.get("B2_KEY_ID")
const B2_MASTER_KEY = Deno.env.get("B2_MASTER_KEY")
const B2_BUCKET_NAME = Deno.env.get("B2_BUCKET_NAME")
const B2_BUCKET_ID = Deno.env.get("B2_BUCKET_ID")

async function authorizeB2() {
  const credentialsString = `${B2_KEY_ID}:${B2_MASTER_KEY}`
  const credentialsBase64 = encodeBase64(credentialsString)

  const response = await fetch("https://api.backblazeb2.com/b2api/v2/b2_authorize_account", {
    method: "POST",
    headers: {
      Authorization: `Basic ${credentialsBase64}`,
    },
  })

  if (!response.ok) {
    throw new Error(`B2 Auth failed: ${response.statusText}`)
  }

  return await response.json()
}

async function getUploadUrl(authToken: string, apiUrl: string) {
  const response = await fetch(`${apiUrl}/b2api/v2/b2_get_upload_url`, {
    method: "POST",
    headers: {
      Authorization: authToken,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      bucketId: B2_BUCKET_ID,
    }),
  })

  if (!response.ok) {
    throw new Error(`Get upload URL failed: ${response.statusText}`)
  }

  return await response.json()
}

async function sha1(data: Uint8Array): Promise<string> {
  const hashBuffer = await crypto.subtle.digest("SHA-1", data)
  const hashArray = Array.from(new Uint8Array(hashBuffer))
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("")
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const url = new URL(req.url)
    const action = url.searchParams.get("action")

    if (!action) {
      return new Response(JSON.stringify({ error: "Missing action parameter" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    // Upload file to B2
    if (action === "uploadFile") {
      const key = url.searchParams.get("key")
      const contentType = url.searchParams.get("contentType") || "image/jpeg"

      if (!key) {
        return new Response(JSON.stringify({ error: "Missing key parameter" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        })
      }

      // Parse JSON body (file is base64-encoded)
      const body = await req.json()
      const base64File = body.file

      if (!base64File) {
        return new Response(JSON.stringify({ error: "Missing file data" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        })
      }

      // Decode base64 to binary
      const binaryString = atob(base64File)
      const fileBytes = new Uint8Array(binaryString.length)
      for (let i = 0; i < binaryString.length; i++) {
        fileBytes[i] = binaryString.charCodeAt(i)
      }

      console.log(`📤 Uploading to B2: ${key} (${fileBytes.length} bytes)`)

      // Authorize with B2
      const authData = await authorizeB2()
      const { authorizationToken, apiUrl, downloadUrl } = authData

      // Get upload URL
      const uploadUrlData = await getUploadUrl(authData.authorizationToken, apiUrl)
      const { uploadUrl, authorizationToken: uploadToken } = uploadUrlData

      // Calculate SHA1
      const hashHex = await sha1(fileBytes)

      // Upload to B2
      const uploadResponse = await fetch(uploadUrl, {
        method: "POST",
        headers: {
          Authorization: uploadToken,
          "X-Bz-File-Name": encodeURIComponent(key),
          "X-Bz-Content-Type": contentType,
          "X-Bz-Content-Sha1": hashHex,
        },
        body: fileBytes,
      })

      if (!uploadResponse.ok) {
        console.error(`❌ B2 upload failed: ${uploadResponse.status}`)
        throw new Error(`Upload failed: ${uploadResponse.statusText}`)
      }

      const uploadResult = await uploadResponse.json()
      const publicUrl = `${downloadUrl}/file/${B2_BUCKET_NAME}/${encodeURIComponent(key)}`

      console.log(`✅ Upload successful: ${key}`)

      return new Response(
        JSON.stringify({
          success: true,
          key,
          publicUrl,
          fileId: uploadResult.fileId,
          contentSha1: uploadResult.contentSha1,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      )
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  } catch (error) {
    console.error("B2 Storage error:", error)
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : "Storage operation failed",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    )
  }
})

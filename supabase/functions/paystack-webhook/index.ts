// Paystack posts transaction events here, signed with an HMAC-SHA512 of
// the raw body using the secret key. Must verify before trusting the
// payload — Paystack docs: https://paystack.com/docs/payments/webhooks/

import { corsHeaders } from "../_shared/cors.ts";
import { serviceClient, updateTransactionByProviderRef } from "../_shared/payments.ts";

const PAYSTACK_SECRET_KEY = Deno.env.get("PAYSTACK_SECRET_KEY")!;

async function verifySignature(rawBody: string, signature: string | null): Promise<boolean> {
  if (!signature) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(PAYSTACK_SECRET_KEY),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(rawBody));
  const computed = Array.from(new Uint8Array(mac))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return computed === signature;
}

Deno.serve(async (req: Request) => {
  const signature = req.headers.get("x-paystack-signature");
  const rawBody = await req.text();

  if (!(await verifySignature(rawBody, signature))) {
    return new Response("Invalid signature", { status: 400 });
  }

  const event = JSON.parse(rawBody);
  const db = serviceClient();
  const reference = event.data?.reference;

  if (reference) {
    switch (event.event) {
      case "charge.success":
        await updateTransactionByProviderRef(db, "paystack", reference, "succeeded", event);
        break;
      case "charge.failed":
        await updateTransactionByProviderRef(db, "paystack", reference, "failed", event);
        break;
      default:
        break;
    }
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});

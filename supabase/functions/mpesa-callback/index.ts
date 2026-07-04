// Daraja posts the STK push result here. Unlike Stripe/Paystack, Daraja
// has no request-signing scheme — trust is instead placed in this URL
// being kept secret (only Safaricom's servers should know it) and in
// matching strictly on CheckoutRequestID before ever updating a row.

import { corsHeaders } from "../_shared/cors.ts";
import { serviceClient, updateTransactionByProviderRef } from "../_shared/payments.ts";

Deno.serve(async (req: Request) => {
  const body = await req.json();
  const callback = body?.Body?.stkCallback;

  if (!callback?.CheckoutRequestID) {
    return new Response(JSON.stringify({ received: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const db = serviceClient();
  const checkoutRequestId = callback.CheckoutRequestID as string;
  const succeeded = callback.ResultCode === 0;

  await updateTransactionByProviderRef(
    db,
    "mpesa",
    checkoutRequestId,
    succeeded ? "succeeded" : "failed",
    callback,
  );

  // Daraja requires this exact envelope to stop retrying the callback.
  return new Response(
    JSON.stringify({ ResultCode: 0, ResultDesc: "Accepted" }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});

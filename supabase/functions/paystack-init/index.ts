// Initializes a Paystack hosted-checkout transaction and a matching
// `pending` ledger row. Client opens the returned `authorizationUrl` in
// an in-app webview and watches the ledger row for resolution.

import { corsHeaders } from "../_shared/cors.ts";
import {
  anonClient,
  insertPendingTransaction,
  requireUserId,
  serviceClient,
} from "../_shared/payments.ts";

const PAYSTACK_SECRET_KEY = Deno.env.get("PAYSTACK_SECRET_KEY")!;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const userId = await requireUserId(req, anonClient());
    const { amount, currency = "KES", purpose, referenceId, recipientType, recipientId, email } =
      await req.json();

    if (!amount || !purpose || !email) {
      throw new Error("amount, purpose and email are required");
    }

    const initRes = await fetch("https://api.paystack.co/transaction/initialize", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${PAYSTACK_SECRET_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email,
        amount: Math.round(Number(amount) * 100), // Paystack expects kobo/cents
        currency,
        metadata: { userId, purpose, referenceId: referenceId ?? "" },
      }),
    });

    const initJson = await initRes.json();
    if (!initJson.status) {
      throw new Error(initJson.message ?? "Paystack initialization failed");
    }

    const { authorization_url: authorizationUrl, reference } = initJson.data;

    const db = serviceClient();
    const transaction = await insertPendingTransaction(db, {
      userId,
      purpose,
      referenceId,
      provider: "paystack",
      providerRef: reference,
      amount: Number(amount),
      currency,
      recipientType,
      recipientId,
    });

    return new Response(
      JSON.stringify({ authorizationUrl, transactionId: transaction.id }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// Creates a Stripe PaymentIntent and a matching `pending` ledger row.
// Client calls this via `client.functions.invoke('stripe-create-intent', ...)`
// then confirms the returned client_secret with the Stripe Flutter SDK.

import Stripe from "npm:stripe@16";
import { corsHeaders } from "../_shared/cors.ts";
import {
  anonClient,
  insertPendingTransaction,
  requireUserId,
  serviceClient,
} from "../_shared/payments.ts";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-06-20",
});

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const userId = await requireUserId(req, anonClient());
    const body = await req.json();
    const {
      amount,
      currency = "usd",
      purpose,
      referenceId,
      recipientType,
      recipientId,
    } = body;

    if (!amount || !purpose) {
      throw new Error("amount and purpose are required");
    }

    const intent = await stripe.paymentIntents.create({
      amount: Math.round(Number(amount) * 100), // Stripe expects the smallest currency unit
      currency,
      metadata: { userId, purpose, referenceId: referenceId ?? "" },
      automatic_payment_methods: { enabled: true },
    });

    const db = serviceClient();
    const transaction = await insertPendingTransaction(db, {
      userId,
      purpose,
      referenceId,
      provider: "stripe",
      providerRef: intent.id,
      amount: Number(amount),
      currency: currency.toUpperCase(),
      recipientType,
      recipientId,
    });

    return new Response(
      JSON.stringify({
        clientSecret: intent.client_secret,
        transactionId: transaction.id,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

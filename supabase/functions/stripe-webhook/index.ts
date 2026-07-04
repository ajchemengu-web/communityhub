// Stripe posts payment lifecycle events here. Signature verification is
// mandatory — this is the only trustworthy source of truth for whether
// money actually moved.

import Stripe from "npm:stripe@16";
import { corsHeaders } from "../_shared/cors.ts";
import { serviceClient, updateTransactionByProviderRef } from "../_shared/payments.ts";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-06-20",
});
const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;

Deno.serve(async (req: Request) => {
  const signature = req.headers.get("stripe-signature");
  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      body,
      signature!,
      webhookSecret,
    );
  } catch (err) {
    return new Response(`Webhook signature verification failed: ${(err as Error).message}`, {
      status: 400,
    });
  }

  const db = serviceClient();

  switch (event.type) {
    case "payment_intent.succeeded": {
      const intent = event.data.object as Stripe.PaymentIntent;
      await updateTransactionByProviderRef(db, "stripe", intent.id, "succeeded", event);
      break;
    }
    case "payment_intent.payment_failed": {
      const intent = event.data.object as Stripe.PaymentIntent;
      await updateTransactionByProviderRef(db, "stripe", intent.id, "failed", event);
      break;
    }
    case "payment_intent.canceled": {
      const intent = event.data.object as Stripe.PaymentIntent;
      await updateTransactionByProviderRef(db, "stripe", intent.id, "cancelled", event);
      break;
    }
    default:
      // Ignore events we don't act on.
      break;
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});

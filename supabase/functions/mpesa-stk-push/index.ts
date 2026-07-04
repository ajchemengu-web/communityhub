// Initiates an M-Pesa STK push via Safaricom's Daraja API and a matching
// `pending` ledger row keyed by CheckoutRequestID. There is no client SDK
// for M-Pesa — the Flutter app calls this function, then watches the
// ledger row over Supabase Realtime until `mpesa-callback` resolves it.

import { corsHeaders } from "../_shared/cors.ts";
import {
  anonClient,
  insertPendingTransaction,
  requireUserId,
  serviceClient,
} from "../_shared/payments.ts";

const CONSUMER_KEY = Deno.env.get("MPESA_CONSUMER_KEY")!;
const CONSUMER_SECRET = Deno.env.get("MPESA_CONSUMER_SECRET")!;
const SHORTCODE = Deno.env.get("MPESA_SHORTCODE")!;
const PASSKEY = Deno.env.get("MPESA_PASSKEY")!;
const CALLBACK_URL = Deno.env.get("MPESA_CALLBACK_URL")!; // public URL of mpesa-callback function
// Sandbox by default; set MPESA_ENV=production for go-live.
const BASE_URL = Deno.env.get("MPESA_ENV") === "production"
  ? "https://api.safaricom.co.ke"
  : "https://sandbox.safaricom.co.ke";

function timestamp(): string {
  const d = new Date();
  const pad = (n: number) => n.toString().padStart(2, "0");
  return (
    `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}` +
    `${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`
  );
}

async function getAccessToken(): Promise<string> {
  const credentials = btoa(`${CONSUMER_KEY}:${CONSUMER_SECRET}`);
  const res = await fetch(
    `${BASE_URL}/oauth/v1/generate?grant_type=client_credentials`,
    { headers: { Authorization: `Basic ${credentials}` } },
  );
  const json = await res.json();
  if (!json.access_token) throw new Error("Failed to obtain Daraja access token");
  return json.access_token;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const userId = await requireUserId(req, anonClient());
    const {
      amount,
      phoneNumber, // MSISDN in 2547XXXXXXXX format
      purpose,
      referenceId,
      recipientType,
      recipientId,
      accountReference = "CommunityHub",
    } = await req.json();

    if (!amount || !phoneNumber || !purpose) {
      throw new Error("amount, phoneNumber and purpose are required");
    }

    const ts = timestamp();
    const password = btoa(`${SHORTCODE}${PASSKEY}${ts}`);
    const accessToken = await getAccessToken();

    const stkRes = await fetch(`${BASE_URL}/mpesa/stkpush/v1/processrequest`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        BusinessShortCode: SHORTCODE,
        Password: password,
        Timestamp: ts,
        TransactionType: "CustomerPayBillOnline",
        Amount: Math.round(Number(amount)),
        PartyA: phoneNumber,
        PartyB: SHORTCODE,
        PhoneNumber: phoneNumber,
        CallBackURL: CALLBACK_URL,
        AccountReference: accountReference,
        TransactionDesc: purpose,
      }),
    });

    const stkJson = await stkRes.json();
    if (stkJson.ResponseCode !== "0") {
      throw new Error(stkJson.errorMessage ?? stkJson.ResponseDescription ?? "STK push failed");
    }

    const checkoutRequestId = stkJson.CheckoutRequestID;

    const db = serviceClient();
    const transaction = await insertPendingTransaction(db, {
      userId,
      purpose,
      referenceId,
      provider: "mpesa",
      providerRef: checkoutRequestId,
      amount: Number(amount),
      currency: "KES",
      recipientType,
      recipientId,
    });

    return new Response(
      JSON.stringify({ checkoutRequestId, transactionId: transaction.id }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

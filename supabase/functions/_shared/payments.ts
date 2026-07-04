import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

export type PaymentPurpose = "donation" | "order" | "membership" | "boost";
export type PaymentProviderName = "stripe" | "paystack" | "mpesa";
export type PaymentStatus =
  | "pending"
  | "processing"
  | "succeeded"
  | "failed"
  | "cancelled";

export interface CreateTransactionInput {
  userId: string;
  purpose: PaymentPurpose;
  referenceId?: string | null;
  provider: PaymentProviderName;
  providerRef: string;
  amount: number;
  currency?: string;
  recipientType?: "platform" | "community";
  recipientId?: string | null;
  platformFeeAmount?: number | null;
}

/** Service-role client — bypasses RLS. Only ever used inside Edge Functions. */
export function serviceClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

export async function insertPendingTransaction(
  client: SupabaseClient,
  input: CreateTransactionInput,
) {
  const { data, error } = await client
    .from("payment_transactions")
    .insert({
      user_id: input.userId,
      purpose: input.purpose,
      reference_id: input.referenceId ?? null,
      provider: input.provider,
      provider_ref: input.providerRef,
      amount: input.amount,
      currency: input.currency ?? "KES",
      status: "pending",
      recipient_type: input.recipientType ?? "platform",
      recipient_id: input.recipientId ?? null,
      platform_fee_amount: input.platformFeeAmount ?? null,
    })
    .select()
    .single();

  if (error) throw error;
  return data;
}

export async function updateTransactionByProviderRef(
  client: SupabaseClient,
  provider: PaymentProviderName,
  providerRef: string,
  status: PaymentStatus,
  rawPayload?: unknown,
) {
  const { error } = await client
    .from("payment_transactions")
    .update({
      status,
      raw_provider_payload: rawPayload ?? null,
    })
    .eq("provider", provider)
    .eq("provider_ref", providerRef);

  if (error) throw error;
}

/** Flat platform cut — tune per feature later if tiered fees are needed. */
export function computePlatformFee(amount: number, ratePercent = 5): number {
  return Math.round(amount * (ratePercent / 100) * 100) / 100;
}

/** Extracts and validates the calling user's id from the request's JWT. */
export async function requireUserId(
  req: Request,
  anonClient: SupabaseClient,
): Promise<string> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace("Bearer ", "");
  const { data, error } = await anonClient.auth.getUser(token);
  if (error || !data.user) {
    throw new Error("Unauthorized");
  }
  return data.user.id;
}

export function anonClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
  );
}

import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import { Resend } from "npm:resend@4.0.0";

const resend = new Resend(Deno.env.get("RESEND_API_KEY")!);
const hookSecret = Deno.env.get("SEND_EMAIL_HOOK_SECRET")!;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // Verify webhook signature
  const payload = await req.text();
  const headers = Object.fromEntries(req.headers);
  const wh = new Webhook(hookSecret.replace("v1,whsec_", ""));

  let data: {
    user: { email: string };
    email_data: {
      token: string;
      token_hash: string;
      redirect_to: string;
      email_action_type: string;
    };
  };

  try {
    data = wh.verify(payload, headers) as typeof data;
  } catch (err) {
    console.error("Webhook verification failed:", err);
    return new Response(
      JSON.stringify({
        error: { http_code: 401, message: "Invalid signature" },
      }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  const { user, email_data } = data;
  const action = email_data.email_action_type;
  const token = email_data.token;

  // Build email content
  const subject = {
    signup: "Verify your TestTrack account",
    recovery: "Reset your TestTrack password",
    magic_link: "Your TestTrack login link",
    email_change: "Confirm your new email",
  }[action] ?? "TestTrack verification code";

  const html = `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 480px; margin: 0 auto; padding: 40px 20px;">
      <h2 style="color: #1E0F35; margin-bottom: 24px;">
        ${action === "signup" ? "Welcome to TestTrack" : action === "recovery" ? "Reset your password" : action === "email_change" ? "Confirm email change" : "TestTrack"}
      </h2>
      <p style="color: #444; font-size: 16px;">Your verification code is:</p>
      <h1 style="letter-spacing: 8px; font-size: 36px; font-family: monospace; color: #5B3491; background: #F5F0FB; padding: 16px 24px; border-radius: 12px; text-align: center;">${token}</h1>
      <p style="color: #888; font-size: 14px;">Enter this code in the app. It expires in 1 hour.</p>
    </div>
  `;

  // Send via Resend
  try {
    const { error } = await resend.emails.send({
      from: "TestTrack <noreply@polarindustries.co>",
      to: [user.email],
      subject,
      html,
    });

    if (error) {
      console.error("Resend error:", error);
      return new Response(
        JSON.stringify({
          error: { http_code: 500, message: error.message },
        }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  } catch (err) {
    console.error("Resend send failed:", err);
    return new Response(
      JSON.stringify({
        error: { http_code: 500, message: err.message },
      }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  return new Response(JSON.stringify({}), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});

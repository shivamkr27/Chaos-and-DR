// Lambda function — receives failover event from Cloudflare Worker → publishes to SNS
// Runtime: Node.js 20.x  |  Handler: index.handler
// Env vars required: SNS_TOPIC_ARN, ALERT_SECRET

const crypto = require("crypto");
const { SNSClient, PublishCommand } = require("@aws-sdk/client-sns");

const sns = new SNSClient({ region: process.env.AWS_REGION || "us-east-1" });

function safeCompare(a, b) {
  try {
    return crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b));
  } catch {
    return false;
  }
}

exports.handler = async (event) => {
  const secret = (event.headers || {})["x-alert-secret"];
  const expected = process.env.ALERT_SECRET || "";
  if (!secret || !safeCompare(secret, expected)) {
    return { statusCode: 403, body: "Forbidden" };
  }

  let body = {};
  try { body = JSON.parse(event.body || "{}"); } catch (_) {}

  const now  = new Date().toISOString();
  const path = body.path || "/";
  const msg  = [
    "CHAOS-DR FAILOVER ALERT",
    "",
    `Time    : ${now}`,
    `Status  : PRIMARY DOWN — traffic routed to DR (us-west-2)`,
    `Path    : ${path}`,
    `Worker  : https://chaos-dr-failove.shivamkumarbxr8.workers.dev`,
    "",
    "Primary will recover automatically when the EC2 is back up.",
    "No manual action needed.",
  ].join("\n");

  await sns.send(new PublishCommand({
    TopicArn: process.env.SNS_TOPIC_ARN,
    Subject:  "Chaos-DR: Primary Region Failover Detected",
    Message:  msg,
  }));

  return {
    statusCode: 200,
    body: JSON.stringify({ sent: true, timestamp: now }),
  };
};

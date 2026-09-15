import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  experimental: { serverActions: { bodySizeLimit: "3mb" } },
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "*.supabase.co" }, // vessel-media
    ],
  },
};

export default nextConfig;

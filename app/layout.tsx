import { getLocale } from "@/lib/i18n/server";
import { LocaleProvider } from "@/components/ui/LocaleProvider";
import { Sora, Inter, JetBrains_Mono } from "next/font/google";
import "./globals.css";

// Las 3 familias que tailwind.config.ts espera vía CSS variables —
// nunca se cargaban de verdad antes de esta corrección, el fallback
// genérico de Tailwind (sans-serif/monospace) las enmascaraba lo
// suficiente como para no notarse a simple vista.
const sora = Sora({
  subsets: ["latin"],
  variable: "--font-sora",
  display: "swap",
});
const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});
const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-jetbrains",
  display: "swap",
});

export const metadata = {
  title: "KCC Marine Cloud",
  robots: { index: false, follow: false },
  manifest: "/manifest.json",
};
export const viewport = {
  themeColor: "#0D1220",
  width: "device-width",
  initialScale: 1,
};

export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const locale = await getLocale();
  return (
    <html
      lang={locale}
      className={`${sora.variable} ${inter.variable} ${jetbrainsMono.variable}`}
    >
      <body>
        <LocaleProvider locale={locale}>{children}</LocaleProvider>
      </body>
    </html>
  );
}

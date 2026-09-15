import { getLocale } from "@/lib/i18n/server";
import { dictionary } from "@/lib/i18n/dictionary";
import { LoginForm } from "@/components/auth/LoginForm";
import { LanguageSwitch } from "@/components/ui/LanguageSwitch";
import { KccLogo } from "@/components/ui/KccLogo";

const ICONS = ["⌁", "⚙", "▥", "◎"] as const;

export default async function LoginPage() {
  const locale = await getLocale();
  const t = dictionary[locale];
  const features = [
    t.login.feature1,
    t.login.feature2,
    t.login.feature3,
    t.login.feature4,
  ];

  return (
    <div className="min-h-screen relative overflow-hidden bg-[#04101c]">
      <div className="absolute inset-0 hero-marine !rounded-none !border-0" />
      <div className="absolute inset-0 bg-[linear-gradient(90deg,rgba(3,10,19,.9)_0%,rgba(3,10,19,.58)_48%,rgba(3,10,19,.76)_100%)]" />
      <div className="absolute inset-0 marine-waves opacity-80 pointer-events-none" />

      <div className="relative z-10 min-h-screen grid lg:grid-cols-[1.08fr_.92fr]">
        <section className="flex flex-col justify-between px-6 pt-10 pb-0 lg:p-12 xl:p-16">
          <div className="flex items-center gap-6 eyebrow text-silver/70">
            <span>KCC Marine Cloud</span>
            <span className="w-20 h-px bg-gold-dim" />
            <span>
              {locale === "es"
                ? "Navegamos un futuro más fuerte"
                : "Navigating a stronger future"}
            </span>
          </div>
          <div className="max-w-[560px] pt-8 lg:pt-0 lg:pb-10">
            <h1 className="font-display text-[36px] lg:text-[54px] xl:text-[62px] leading-[.96] font-semibold tracking-[-.035em] text-white drop-shadow-2xl">
              {locale === "es" ? (
                <>
                  Más que
                  <br />
                  mantenimiento,
                  <br />
                  <span className="text-gold-sheen">
                    un mar de
                    <br />
                    posibilidades.
                  </span>
                </>
              ) : (
                <>
                  More than
                  <br />
                  maintenance,
                  <br />
                  <span className="text-gold-sheen">
                    a sea of
                    <br />
                    possibilities.
                  </span>
                </>
              )}
            </h1>
            <div className="w-16 h-[2px] bg-gold mt-7 mb-6" />
            <p className="text-[17px] text-[#d0d9e6] max-w-md leading-relaxed">
              {t.login.subtitle}
            </p>
            <div className="hidden lg:grid grid-cols-2 gap-x-9 gap-y-5 mt-9 max-w-lg">
              {features.map((f, i) => (
                <div
                  key={f}
                  className="flex items-center gap-3 text-sm text-[#e2e9f2]"
                >
                  <span className="h-10 w-10 rounded-full border border-gold-dim/55 bg-[#091827]/75 flex items-center justify-center text-gold-bright shadow-[0_0_24px_-14px_rgba(228,199,122,.8)]">
                    {ICONS[i]}
                  </span>
                  <span>{f}</span>
                </div>
              ))}
            </div>
          </div>
          <div className="hidden lg:block eyebrow text-silver/50">
            Marine Solutions · Technology · Excellence
          </div>
        </section>

        <section className="flex items-center justify-center px-5 py-8 sm:p-10 lg:p-12 xl:p-16">
          <div className="w-full max-w-[500px]">
            <div className="flex justify-end mb-4">
              <LanguageSwitch current={locale} variant="onDark" />
            </div>
            <div className="relative overflow-hidden rounded-[28px] border border-gold-dim/45 bg-[#071422]/88 backdrop-blur-2xl p-7 sm:p-9 shadow-[0_35px_100px_-45px_rgba(0,0,0,.98),0_0_50px_-30px_rgba(228,199,122,.75)]">
              <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-gold-bright to-transparent opacity-80" />
              <div className="absolute -right-20 -top-20 h-56 w-56 rounded-full bg-gold/[.08] blur-3xl" />
              <div className="relative flex justify-center mb-4">
                <KccLogo size="lg" className="w-[230px] h-[155px]" />
              </div>
              <div className="relative text-center mb-7">
                <div className="eyebrow text-silver/80 mb-2">
                  KCC Marine Cloud
                </div>
                <h2 className="font-display text-2xl font-semibold text-white">
                  {t.login.welcomeBack}
                </h2>
                <p className="text-sm text-cool-gray mt-2 max-w-sm mx-auto leading-relaxed">
                  {t.login.welcomeSub}
                </p>
              </div>
              <LoginForm t={t} />
              <div className="mt-7 pt-5 border-t border-white/[.06] text-center eyebrow text-silver/35">
                Navigating a stronger future
              </div>
            </div>
            <p className="mt-5 text-center text-[11px] text-cool-gray/55">
              {t.common.accessByInvitation}
            </p>
          </div>
        </section>
      </div>
    </div>
  );
}

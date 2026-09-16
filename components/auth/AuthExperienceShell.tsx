import { KccLogo } from '@/components/ui/KccLogo';

type Step = {
  label: string;
  state: 'done' | 'active' | 'upcoming';
};

export function AuthExperienceShell({
  eyebrow,
  title,
  description,
  children,
  steps,
}: {
  eyebrow: string;
  title: string;
  description: string;
  children: React.ReactNode;
  steps?: Step[];
}) {
  return (
    <main className="auth-experience min-h-screen">
      <div className="auth-orbit auth-orbit-a" aria-hidden="true" />
      <div className="auth-orbit auth-orbit-b" aria-hidden="true" />
      <div className="auth-waterline" aria-hidden="true" />

      <section className="auth-experience-grid">
        <div className="auth-story-panel">
          <div className="auth-story-topline">
            <KccLogo size="sm" />
            <span className="auth-live-pill"><i /> Secure access</span>
          </div>

          <div className="auth-story-copy">
            <p className="eyebrow">KCC Marine Cloud</p>
            <h2>One account.<br /><span className="text-gold-sheen">Every voyage.</span></h2>
            <p>
              Company teams, technicians and customers use the same secure identity — with the right workspace waiting after sign-in.
            </p>
          </div>

          <div className="auth-story-status">
            <div><span>01</span><p>Secure identity</p></div>
            <div><span>02</span><p>Role-aware workspace</p></div>
            <div><span>03</span><p>Protected operations</p></div>
          </div>
        </div>

        <div className="auth-action-wrap">
          <div className="auth-action-card">
            <div className="auth-card-glow" aria-hidden="true" />
            <p className="eyebrow">{eyebrow}</p>
            <h1>{title}</h1>
            <p className="auth-action-description">{description}</p>

            {steps?.length ? (
              <div className="auth-stepper" aria-label="Account setup progress">
                {steps.map((step, index) => (
                  <div key={step.label} className={`auth-step auth-step-${step.state}`}>
                    <span>{step.state === 'done' ? '✓' : index + 1}</span>
                    <p>{step.label}</p>
                  </div>
                ))}
              </div>
            ) : null}

            <div className="auth-action-content">{children}</div>
          </div>
          <p className="auth-footnote">Marine Solutions · Technology · Excellence</p>
        </div>
      </section>
    </main>
  );
}

export type Locale = 'en' | 'es';
export const DEFAULT_LOCALE: Locale = 'en';

export interface Dictionary {
  common: {
    signIn: string;
    signingIn: string;
    email: string;
    password: string;
    rememberMe: string;
    forgotPassword: string;
    requestAccessLink: string;
    invalidCredentials: string;
    accessByInvitation: string;
    cancel: string;
    save: string;
  };
  login: {
    tagline: string;
    subtitle: string;
    welcomeBack: string;
    welcomeSub: string;
    feature1: string;
    feature2: string;
    feature3: string;
    feature4: string;
  };
  status: {
    request_received: string;
    triage: string;
    estimate: string;
    awaiting_approval: string;
    scheduled: string;
    technician_assigned: string;
    en_route: string;
    checked_in: string;
    diagnosis: string;
    work_in_progress: string;
    waiting_parts: string;
    waiting_customer_approval: string;
    quality_control: string;
    invoice: string;
    payment: string;
    completed: string;
    warranty: string;
    cancelled: string;
    open: string;
    overdue: string;
    partially_paid: string;
    paid: string;
    draft: string;
    sent: string;
    approved: string;
    declined: string;
    void: string;
    active: string;
    inactive: string;
    suspended: string;
    archived: string;
    pending_verification: string;
    verified: string;
    rejected: string;
    reversed: string;
  };
  customerPortal: {
    myServices: string;
    myVessel: string;
    invoicesPayments: string;
    warranty: string;
    support: string;
  };
}

// Diccionario centralizado — nunca traducir enums de la base de datos
// directamente en cada componente. Cualquier texto nuevo orientado al
// usuario se agrega acá, no como string suelto en la pantalla.
export const dictionary: Record<Locale, Dictionary> = {
  en: {
    common: {
      signIn: 'Sign In',
      signingIn: 'Signing in…',
      email: 'Email',
      password: 'Password',
      rememberMe: 'Remember me on this device',
      forgotPassword: 'Forgot your password?',
      requestAccessLink: 'Get a sign-in link instead',
      invalidCredentials: 'Invalid email or password.',
      accessByInvitation: 'First-time access starts with a secure invitation. After activation, sign in anytime with your email and password.',
      cancel: 'Cancel',
      save: 'Save',
    },
    login: {
      tagline: 'More than maintenance, a sea of possibilities.',
      subtitle: 'Marine technology, assistance, and control in one place.',
      welcomeBack: 'Sign in to KCC Marine Cloud',
      welcomeSub: 'Secure access to your workspace, operations, and services.',
      feature1: 'Safer vessels',
      feature2: 'More efficient operations',
      feature3: 'Sharper decisions',
      feature4: 'A team that stays connected',
    },
    status: {
      request_received: 'Request Received',
      triage: 'Triage',
      estimate: 'Estimate',
      awaiting_approval: 'Awaiting Approval',
      scheduled: 'Scheduled',
      technician_assigned: 'Technician Assigned',
      en_route: 'Technician en route',
      checked_in: 'Checked In',
      diagnosis: 'Diagnosis',
      work_in_progress: 'In Progress',
      waiting_parts: 'Waiting on Parts',
      waiting_customer_approval: 'Awaiting Your Approval',
      quality_control: 'Quality Control',
      invoice: 'Invoice',
      payment: 'Payment',
      completed: 'Completed',
      warranty: 'Warranty',
      cancelled: 'Cancelled',
      open: 'Open',
      overdue: 'Overdue',
      partially_paid: 'Partially Paid',
      paid: 'Paid',
      draft: 'Draft',
      sent: 'Sent',
      approved: 'Approved',
      declined: 'Declined',
      void: 'Void',
      active: 'Active',
      inactive: 'Inactive',
      suspended: 'Suspended',
      archived: 'Archived',
      pending_verification: 'Pending Verification',
      verified: 'Verified',
      rejected: 'Rejected',
      reversed: 'Reversed',
    },
    customerPortal: {
      myServices: 'My Services',
      myVessel: 'My Vessel',
      invoicesPayments: 'Invoices & Payments',
      warranty: 'Warranty',
      support: 'Support / Chat',
    },
  },
  es: {
    common: {
      signIn: 'Iniciar sesión',
      signingIn: 'Iniciando sesión…',
      email: 'Correo electrónico',
      password: 'Contraseña',
      rememberMe: 'Recordarme en este dispositivo',
      forgotPassword: '¿Olvidé mi contraseña?',
      requestAccessLink: 'Recibir enlace de acceso',
      invalidCredentials: 'Correo o contraseña inválidos.',
      accessByInvitation: 'El primer acceso comienza con una invitación segura. Después de activarte, entra cuando quieras con tu correo y contraseña.',
      cancel: 'Cancelar',
      save: 'Guardar',
    },
    login: {
      tagline: 'Más que mantenimiento, un mar de posibilidades.',
      subtitle: 'Tecnología marina, asistencia y control en un solo lugar.',
      welcomeBack: 'Inicia sesión en KCC Marine Cloud',
      welcomeSub: 'Acceso seguro a tu espacio de trabajo, operaciones y servicios.',
      feature1: 'Embarcaciones más seguras',
      feature2: 'Operaciones más eficientes',
      feature3: 'Decisiones con mayor visión',
      feature4: 'Un equipo siempre conectado',
    },
    status: {
      request_received: 'Solicitud recibida',
      triage: 'Evaluación inicial',
      estimate: 'Presupuesto',
      awaiting_approval: 'Esperando aprobación',
      scheduled: 'Programado',
      technician_assigned: 'Técnico asignado',
      en_route: 'Técnico en camino',
      checked_in: 'Llegó al lugar',
      diagnosis: 'Diagnóstico',
      work_in_progress: 'En progreso',
      waiting_parts: 'Esperando piezas',
      waiting_customer_approval: 'Esperando tu aprobación',
      quality_control: 'Control de calidad',
      invoice: 'Factura',
      payment: 'Pago',
      completed: 'Completado',
      warranty: 'Garantía',
      cancelled: 'Cancelado',
      open: 'Abierto',
      overdue: 'Vencido',
      partially_paid: 'Pago parcial',
      paid: 'Pagado',
      draft: 'Borrador',
      sent: 'Enviado',
      approved: 'Aprobado',
      declined: 'Rechazado',
      void: 'Anulado',
      active: 'Activo',
      inactive: 'Inactivo',
      suspended: 'Suspendido',
      archived: 'Archivado',
      pending_verification: 'Pendiente de verificación',
      verified: 'Verificado',
      rejected: 'Rechazado',
      reversed: 'Revertido',
    },
    customerPortal: {
      myServices: 'Mis servicios',
      myVessel: 'Mi embarcación',
      invoicesPayments: 'Facturas y pagos',
      warranty: 'Garantía',
      support: 'Soporte / Chat',
    },
  },
};

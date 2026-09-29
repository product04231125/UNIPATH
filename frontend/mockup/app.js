"use strict";

const STATUS = {
  satisfied: { label: "충족", tone: "ok" },
  not_satisfied: { label: "미충족", tone: "bad" },
  needs_review: { label: "확인 필요", tone: "warn" },
  not_applicable: { label: "판정 없음", tone: "mute" },
  insufficient_evidence: { label: "근거 부족", tone: "info" },
  cited: { label: "근거 있음", tone: "ok" },
  missing_required: { label: "필수 부족", tone: "bad" },
  met: { label: "충족", tone: "ok" },
  missing: { label: "부족", tone: "bad" },
  unknown: { label: "정보 부족", tone: "warn" },
  not_evaluated: { label: "비교 제외", tone: "mute" },
  empty: { label: "규칙 없음", tone: "mute" },
};

const DOC = {
  id: "a6e538bc-8317-4b27-b41a-2bc3d6a3d832",
  title: "컴퓨터공학과 졸업최소이수학점",
  file: "docs/sources/경동대학교_컴퓨터공학과_2026학년도_졸업최소이수학점.pdf",
  pages: "1–2쪽",
  url: null,
  hash: "2778B9AAA1D2E248D9FBD15A0960B3201342E939A8881A5FC48C6493C05250FB",
};

const CERT_DOC = {
  id: "9b2e1c70-4d8a-4f1e-9c3b-c984ce908cce",
  title: "컴퓨터공학과 졸업자격요건",
  file: "docs/sources/경동대학교_컴퓨터공학과_졸업인증요건.pdf",
  pages: "1–3쪽",
  url: null,
  hash: "C984CE908CCE3BDCC00D42C9A363CED1CEDFB9FC2EB4551B213D97A453A0F036",
};

const QNET_CREDENTIAL_HINTS = [
  {
    name: "정보처리기사",
    reason: "학과 졸업인증 전공영역 · 채용 비교에서 확인 필요",
    eligibility: "응시자격은 학교 이수·경력 기준으로 Q-Net에서 확인",
    schedule: "접수·시험 일정은 Q-Net API 동기화 대상",
  },
];

const RULE_SCOPES = [
  { id: "institution", label: "대학 공통", hint: "university" },
  { id: "curriculum", label: "내 교육과정", hint: "curriculum" },
  { id: "department", label: "학과 기준", hint: "department" },
];

const RULE_SETS = [
  {
    id: "set-kd-common-degree",
    scope: "institution",
    name: "경동대학교 일반 학부 졸업 기준",
    range: "일반과정 · 학부생",
    status: "not_satisfied",
    ruleCount: 4,
  },
  {
    id: "set-kd-cs-cert",
    scope: "department",
    name: "컴퓨터공학과 졸업인증제",
    range: "창의영역 택 1 + 전공영역 택 1",
    status: "needs_review",
    ruleCount: 9,
  },
  {
    id: "set-kd-cs-min",
    scope: "curriculum",
    name: "컴퓨터공학과 졸업최소이수학점",
    range: "2024–2021 단일전공",
    status: "not_satisfied",
    ruleCount: 10,
  },
];

const COMMON_DEGREE_RULES = [
  { id: "common-total", title: "최소 총 취득학점 120학점", value: "88 / 120학점", status: "not_satisfied", source: "학칙 제34조 · 졸업(수료)자격심사 규정 제2조", note: "총 취득학점은 학교 화면 값입니다. 학과별 교육과정의 교과영역 최소학점은 아래 ‘내 교육과정 기준’에서 별도로 판정합니다." },
  { id: "common-terms", title: "일반 졸업 등록학기 8학기 이상", value: "학적 확인 필요", status: "needs_review", source: "졸업(수료)자격심사 규정 제2조", note: "학교 학적 시스템에서 등록학기를 확인해 주세요. 조기졸업·편입 등 예외는 학사 담당 부서에 확인하세요." },
  { id: "common-required", title: "필수 교과목 및 필수 P/N 교과목 이수", value: "과목별 확인 필요", status: "needs_review", source: "졸업(수료)자격심사 규정 제2조", note: "학교 성적 시스템에서 필수과목 이수와 P/N 합격 여부를 확인해 주세요." },
  { id: "common-volunteer", title: "사회봉사활동 교양필수 이수", value: "학교 승인 시간 확인 필요", status: "needs_review", source: "사회봉사활동 운영 규정 제4조·제6조", note: "학교에서 승인된 봉사 시간을 확인한 뒤 이곳에도 등록해 주세요." },
];

const DEPT_RULES = [
  { id: "dept-cert-combo", setId: "set-kd-cs-cert", group: "졸업인증제", title: "창의영역 택 1 + 전공영역 택 1", status: "needs_review", page: 1, note: "컴퓨터공학과 행은 창의·전공 칸이 ○입니다. 두 영역을 함께 채워야 합니다. 창의는 입력 TOEIC으로 채웠고, 전공영역은 확인 필요라 묶음 전체는 확인 필요입니다." },
  { id: "dept-exempt", setId: "set-kd-cs-cert", group: "졸업인증제", title: "계약학과·직장인 교과과정 면제", status: "not_applicable", page: 1, note: "면제는 계약학과 및 직장인 교과과정 대상자입니다. 컴퓨터응용학과(계)만 계약학과 면제로 적혀 있습니다. 정민서는 일반 과정이라 적용하지 않습니다." },
  { id: "dept-work-exam", setId: "set-kd-cs-cert", group: "졸업 요건", title: "졸업작품 발표 또는 졸업시험 등 졸업실적 심사 합격", status: "needs_review", page: 1, note: "졸업 작품 입력은 있으나 심사 합격 여부는 학교 확인 전입니다." },
  { id: "dept-creative", setId: "set-kd-cs-cert", group: "창의영역", title: "창의영역 택 1", status: "satisfied", page: 2, note: "세계화 기타계열 TOEIC 인증점수 500입니다. 입력 점수 850으로 이 경로를 채운 것으로 두었습니다. 정보화·인성/봉사 36시간 등은 택 1이라 추가로 요구하지 않습니다. 자격 공식 확인은 없습니다." },
  { id: "dept-major-i-license", setId: "set-kd-cs-cert", group: "전공영역 I", title: "자격/면허 1개 이상", status: "not_satisfied", page: 3, note: "정보처리기사·산업기사 등 목록과 이름이 같은 자격이 프로필에 없습니다. TOEIC은 창의영역 세계화 항목입니다." },
  { id: "dept-major-i-practice", setId: "set-kd-cs-cert", group: "전공영역 I", title: "실무/실습 1개 이상", status: "needs_review", page: 3, note: "현장실습·비교과·성적 관련 결과는 학교 시스템에서 승인 또는 이수 상태를 확인해 주세요." },
  { id: "dept-major-i", setId: "set-kd-cs-cert", group: "전공영역 I", title: "자격/면허 또는 실무/실습 중 택 1", status: "needs_review", page: 3, note: "자격은 미충족, 실무는 확인 필요라 택 1 결과는 확인 필요입니다." },
  { id: "dept-major-ii", setId: "set-kd-cs-cert", group: "전공영역 II", title: "취업 또는 창업 증빙", status: "not_satisfied", page: 3, note: "4대보험 취업 또는 창업 증빙을 졸업사정 전까지 제출한 기록이 없습니다. 직장인 교과과정 면제 대상도 아닙니다." },
  { id: "dept-major", setId: "set-kd-cs-cert", group: "전공영역", title: "학과졸업인증제 I 또는 II 중 선택", status: "needs_review", page: 3, note: "I는 확인 필요, II는 미충족입니다." },
];

const CREDIT_LINES = [
  { id: "total", setId: "set-kd-cs-min", group: "합계", title: "졸업 최소 이수학점", earned: 88, required: 120, status: "not_satisfied", note: "학교 화면의 총 취득학점만 대응했습니다." },
  { id: "lib-lang", setId: "set-kd-cs-min", group: "교양", title: "외국어", earned: 4, required: 4, status: "satisfied", note: "포털의 외국어 칸과 이름이 같아 대응했습니다." },
  { id: "free", setId: "set-kd-cs-min", group: "자유선택", title: "자유선택", earned: 14, required: 23, status: "not_satisfied", note: "포털의 자유 칸과 대응했습니다." },
  { id: "lib-basic", setId: "set-kd-cs-min", group: "교양", title: "기초교양", earned: null, required: 7, status: "needs_review", note: "포털에 같은 이름 칸이 없어 신청 내역으로 채우지 않았습니다." },
  { id: "lib-kd", setId: "set-kd-cs-min", group: "교양", title: "KD교양", earned: null, required: 5, status: "needs_review", note: "포털에 같은 이름 칸이 없어 신청 내역으로 채우지 않았습니다." },
  { id: "lib-sci", setId: "set-kd-cs-min", group: "교양", title: "기초과학", earned: null, required: 6, status: "needs_review", note: "포털에 같은 이름 칸이 없어 신청 내역으로 채우지 않았습니다." },
  { id: "lib-elec", setId: "set-kd-cs-min", group: "교양", title: "교양선택", earned: null, required: 9, status: "needs_review", note: "교선과 정선 중 어디로 둘지 학교 칸만으로는 정하지 않았습니다." },
  { id: "maj-gen", setId: "set-kd-cs-min", group: "전공", title: "전공필수(일반)", earned: null, required: 6, status: "needs_review", note: "포털 전필과 범위가 같은지 확인이 필요합니다." },
  { id: "maj-basic", setId: "set-kd-cs-min", group: "전공", title: "전공기초필수", earned: null, required: 12, status: "needs_review", note: "포털에 기초필수 칸이 없습니다." },
  { id: "maj-elec", setId: "set-kd-cs-min", group: "전공", title: "전공선택", earned: null, required: 48, status: "needs_review", note: "포털 전선 칸이 이번 수집본에서는 비어 있습니다." },
];

const PORTAL_COLS = [
  { key: "total", label: "총학점", rule: "total" },
  { key: "volunteer", label: "사회봉사", rule: null },
  { key: "gyopil", label: "교필", rule: null },
  { key: "gyoseon", label: "교선", rule: "lib-elec" },
  { key: "foreign", label: "외국어", rule: "lib-lang" },
  { key: "jeontam", label: "전탐", rule: null },
  { key: "balance", label: "균형", rule: null },
  { key: "jeongseon", label: "정선", rule: "lib-elec" },
  { key: "jeonpil", label: "전필", rule: "maj-gen" },
  { key: "jeonseon", label: "전선", rule: "maj-elec" },
  { key: "free", label: "자유", rule: "free" },
  { key: "teaching", label: "교직", rule: null },
  { key: "doubleMajor", label: "복수", rule: null },
  { key: "minor", label: "부전", rule: null },
];

const REG_TO_PORTAL = {
  "교필": "gyopil", "교선": "gyoseon", "외국어": "foreign", "전탐": "jeontam",
  "균형": "balance", "정선": "jeongseon", "전필": "jeonpil", "전선": "jeonseon",
  "자유": "free", "교직": "teaching", "복수": "doubleMajor", "부전": "minor",
};

const SCHOOL_STANDARD = { total: "120", foreign: "4", free: "23" };
const SCHOOL_EARNED = { total: "88", volunteer: "확인 필요", foreign: "4", free: "14" };
const SCHOOL_SHORT = { total: "32", foreign: "0", free: "9" };

const INSTITUTIONS = [
  {
    id: "inst-kd",
    name: "경동대학교",
    departments: [
      { id: "dept-cs", name: "컴퓨터공학과", rules: true },
      { id: "dept-biz", name: "경영학과", rules: false },
    ],
  },
  { id: "inst-hanbit", name: "한빛대학교", departments: [] },
  {
    id: "inst-pureun",
    name: "푸른솔대학교",
    departments: [{ id: "dept-design", name: "시각디자인학과", rules: false }],
  },
];

const CURRENT_TERM = "2026-2";
const REG_CATEGORIES = ["교필", "교선", "외국어", "전탐", "균형", "정선", "전필", "전선", "자유", "교직", "복수", "부전"];

const REGISTRATIONS = [
  { id: "r1", term: "2026-2", code: "CSE210", title: "자료구조", category: "전필", credits: 3, section: "01" },
  { id: "r2", term: "2026-2", code: "CSE401", title: "캡스톤디자인 1", category: "전선", credits: 3, section: "02" },
  { id: "r3", term: "2026-1", code: "CSE342", title: "운영체제", category: "전선", credits: 3, section: "01" },
  { id: "r4", term: "2026-1", code: "CSE351", title: "컴퓨터네트워크", category: "전선", credits: 3, section: "01" },
  { id: "r5", term: "2025-2", code: "CSE331", title: "알고리즘", category: "전필", credits: 3, section: "01" },
  { id: "r6", term: "2025-2", code: "CSE305", title: "데이터베이스", category: "전선", credits: 3, section: "02" },
  { id: "r7", term: "2025-1", code: "CSE220", title: "컴퓨터구조", category: "전필", credits: 3, section: "01" },
  { id: "r8", term: "2025-1", code: "MAT210", title: "선형대수", category: "균형", credits: 3, section: "03" },
  { id: "r9", term: "2024-2", code: "ENG201", title: "영어회화", category: "외국어", credits: 2, section: "04" },
  { id: "r10", term: "2024-2", code: "GED118", title: "대학글쓰기", category: "교필", credits: 3, section: "02" },
  { id: "r11", term: "2024-1", code: "GED101", title: "사고와표현", category: "교필", credits: 3, section: "01" },
  { id: "r12", term: "2024-1", code: "CSE101", title: "프로그래밍기초", category: "전필", credits: 3, section: "05" },
];

const BANDS = [
  { years: "2026–2025", track: "단일전공", liberal: "31", major: "필수 15 · 선택 51 · 계 66", free: "23", total: "120", page: "1" },
  { years: "2026–2025", track: "복수전공", liberal: "—", major: "33", free: "—", total: "120", page: "1", note: "다른 전공과 병행이수" },
  { years: "2026–2025", track: "부전공", liberal: "—", major: "18", free: "—", total: "120", page: "1" },
  { years: "2026–2025", track: "재직자", liberal: "선택 25", major: "선택 45", free: "50", total: "120", page: "1" },
  { years: "2026–2025", track: "외국인", liberal: "—", major: "—", free: "—", total: "120", page: "1" },
  { years: "2024–2021", track: "단일전공", liberal: "31", major: "공통필수 6 · 기초필수 12 · 선택 48 · 계 66", free: "23", total: "120", page: "1–2", applied: true },
  { years: "2024–2021", track: "복수전공", liberal: "—", major: "33", free: "—", total: "120", page: "1–2", note: "다른 전공과 병행이수" },
  { years: "2024–2021", track: "부전공", liberal: "—", major: "18", free: "—", total: "120", page: "1–2" },
  { years: "2024–2021", track: "재직자", liberal: "선택 25", major: "선택 45", free: "50", total: "120", page: "1–2" },
  { years: "2024–2021", track: "외국인", liberal: "—", major: "—", free: "—", total: "120", page: "1–2" },
  { years: "2020", track: "단일전공", liberal: "31", major: "필수 12 · 선택 54 · 계 66", free: "23", total: "120", page: "3" },
  { years: "2020", track: "복수전공", liberal: "—", major: "33", free: "—", total: "120", page: "3" },
  { years: "2020", track: "부전공", liberal: "—", major: "18", free: "—", total: "120", page: "3", note: "다른 전공과 병행이수" },
  { years: "2020", track: "재직자", liberal: "선택 25", major: "선택 45", free: "50", total: "120", page: "3" },
  { years: "2020", track: "외국인", liberal: "—", major: "—", free: "—", total: "120", page: "3" },
  { years: "2019–2018", track: "단일전공", liberal: "37", major: "필수 14 · 선택 56 · 계 70", free: "23", total: "130", page: "3" },
  { years: "2019–2018", track: "복수전공", liberal: "—", major: "필수 4 · 선택 31 · 계 35", free: "—", total: "—", page: "3" },
  { years: "2019–2018", track: "부전공", liberal: "—", major: "필수 4 · 선택 17 · 계 21", free: "—", total: "—", page: "3" },
  { years: "2019–2018", track: "재직자", liberal: "선택 25", major: "선택 48", free: "57", total: "130", page: "3" },
  { years: "2019–2018", track: "외국인", liberal: "선택 33", major: "선택 69", free: "28", total: "130", page: "3" },
];

const state = {
  role: "student",
  screen: "home",
  linked: true,
  openRule: null,
  studyPane: "records",
  auditFilter: "institution",
  auditPreview: "kd",
  mockToolsOpen: false,
  regFilter: "all",
  registrations: REGISTRATIONS.map((row) => ({ ...row })),
  regDraft: { term: CURRENT_TERM, title: "", category: "전선", credits: "3", section: "" },
  regError: "",
  volunteers: [{ id: "v1", title: "교내 봉사", hours: 30 }],
  volunteerDraft: { title: "", hours: "" },
  volunteerError: "",
  experiences: [
    { id: "e1", type: "동아리", title: "축제 운영", organization: "합성 동아리", started: "2025-05-01", ended: "2025-05-03" },
    { id: "e2", type: "아르바이트", title: "서점 근무", organization: "합성 서점", started: "2026-03-01", ended: "" },
  ],
  experienceDraft: { type: "프로젝트", title: "", organization: "", started: "", ended: "" },
  experienceError: "",
  certificates: [{ id: "c1", name: "TOEIC", detail: "850", earned: "2025-11-02" }],
  certificateDraft: { name: "", detail: "", earned: "" },
  certificateError: "",
  works: [{
    id: "w1",
    title: "졸업 프로젝트",
    kind: "프로젝트",
    role: "백엔드 API · 데이터베이스 설계",
    period: "2026.03–2026.06",
    result: "팀 시연 완료",
    url: "",
  }],
  workDraft: { title: "", kind: "프로젝트", role: "", period: "", result: "", url: "" },
  workError: "",
  portfolioPane: "records",
  applicationNotice: "",
  draft: "",
  viewer: null,
  session: null,
  authPane: "login",
  authError: "",
  authDraft: {
    name: "", email: "", password: "", confirm: "",
    schoolQuery: "", institutionId: "", deptQuery: "", departmentId: "",
  },
  linkDraft: { schoolQuery: "", deptQuery: "" },
  noteDraft: { text: "" },
  yearDraft: { year: "" },
  account: null,
  chat: [
    {
      role: "assistant",
      kind: "intro",
      text: "학교·학과·교육과정에 해당하는 공식 문서만 근거로 답합니다. 졸업 가능 여부는 이 대화가 판정하지 않고, 규칙 엔진 결과를 설명합니다.",
    },
  ],
  jobPhase: "idle",
  chatOpen: true,
  chatWidth: 360,
  workspace_type: null,
  workspace_context: null,
  conversation_draft: "",
  suggested_actions: [],
  workspaceThread: [],
  workspaceNotice: "",
  sideOpen: true,
  sideWidth: 224,
};

const CHAT_WIDTH = { def: 360, min: 300, max: 680, collapse: 200, centerMin: 680 };
const SIDE_WIDTH = { def: 224, min: 192, max: 300, icon: 56, collapse: 116 };

const NAV_ICONS = {
  home: `<svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true"><path d="M3.5 8.2 9 3.8l5.5 4.4V15H11v-4H7v4H3.5V8.2Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/></svg>`,
  study: `<svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true"><path d="M3 5.2 9 3l6 2.2v7.1L9 15l-6-2.7V5.2Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/><path d="M9 8.2V15" stroke="currentColor" stroke-width="1.3"/></svg>`,
  records: `<svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true"><path d="M4 3.5h10v11H4v-11Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/><path d="M6.5 7h5M6.5 10h5" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg>`,
  graduation: `<svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true"><path d="m3 7 6-3 6 3-6 3-6-3Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/><path d="M5.2 9.1v3.1c1.8 1.2 5.8 1.2 7.6 0V9.1" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/></svg>`,
  activities: `<svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true"><path d="M4 5h10M4 9h10M4 13h7" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>`,
  experiences: `<svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true"><path d="M4 14.5V6.2L9 3.5l5 2.7v8.3H4Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/><path d="M7 14.5v-3h4v3M7 7.5h.01M11 7.5h.01" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg>`,
  credentials: `<svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true"><path d="m9 3.5 1.5 3 3.3.5-2.4 2.3.6 3.2L9 11l-3 1.5.6-3.2L4.2 7l3.3-.5 1.5-3Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/></svg>`,
  portfolio: `<svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true"><path d="M4 3.5h10v11H4v-11Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/><path d="m6.5 11 1.7-1.8 1.5 1.3 1.7-2 1.6 2.5" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  jobs: `<svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true"><path d="M3.5 7.2h11v6.3H3.5V7.2Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/><path d="M6.5 7.2V5.4A1.4 1.4 0 0 1 7.9 4h2.2A1.4 1.4 0 0 1 11.5 5.4v1.8" stroke="currentColor" stroke-width="1.3"/></svg>`,
  scope: `<svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true"><path d="M3.5 14.5V7.2L9 4.2l5.5 3v7.3H3.5Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/><path d="M7.2 14.5v-4.2h3.6v4.2" stroke="currentColor" stroke-width="1.3"/></svg>`,
  rules: `<svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true"><path d="M4 4.5h10v9H4v-9Z" stroke="currentColor" stroke-width="1.3"/><path d="M4 8h10M8 4.5v9" stroke="currentColor" stroke-width="1.3"/></svg>`,
  docs: `<svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true"><path d="M5 3.5h5.2L13.5 7v7.5H5V3.5Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/><path d="M10.2 3.5V7h3.3" stroke="currentColor" stroke-width="1.3"/></svg>`,
  sources: `<svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true"><path d="M5 3.5h5.2L13.5 7v7.5H5V3.5Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/><path d="M10.2 3.5V7h3.3" stroke="currentColor" stroke-width="1.3"/></svg>`,
  settings: `<svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true"><circle cx="9" cy="9" r="2.2" stroke="currentColor" stroke-width="1.3"/><path d="M9 2.8v1.6M9 13.6v1.6M2.8 9h1.6M13.6 9h1.6M4.5 4.5l1.1 1.1M12.4 12.4l1.1 1.1M13.5 4.5l-1.1 1.1M5.6 12.4l-1.1 1.1" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg>`,
};

const STUDENT_NAV = [
  ["home", "홈", ""],
  ["records", "수강 관리", ""],
  ["graduation", "졸업 요건", ""],
  ["activities", "활동", ""],
  ["experiences", "경험", ""],
  ["credentials", "자격", ""],
  ["portfolio", "포트폴리오·성과", ""],
  ["jobs", "채용 적합도", "2차"],
  ["sources", "공식 문서", ""],
];

const ADMIN_NAV = [
  ["scope", "적용 범위", ""],
  ["rules", "학점 규칙 초안", ""],
  ["docs", "공식 문서", ""],
];

function esc(value) {
  return String(value).replace(/[&<>"']/g, (ch) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[ch]));
}

function stamp(status) {
  const item = STATUS[status] || STATUS.not_applicable;
  return `<span class="stamp ${item.tone}">${item.label}</span>`;
}

function sideWidthNow() {
  return state.sideOpen ? state.sideWidth : SIDE_WIDTH.icon;
}

function chatMaxWidth() {
  return Math.min(CHAT_WIDTH.max, Math.max(CHAT_WIDTH.min, window.innerWidth - sideWidthNow() - CHAT_WIDTH.centerMin));
}

function clampChatWidth(width) {
  return Math.round(Math.min(chatMaxWidth(), Math.max(CHAT_WIDTH.min, width)));
}

function clampSideWidth(width) {
  return Math.round(Math.min(SIDE_WIDTH.max, Math.max(SIDE_WIDTH.min, width)));
}

function applyChatWidth(width) {
  const next = Math.round(Math.min(chatMaxWidth(), Math.max(CHAT_WIDTH.collapse, width)));
  const workspace = document.querySelector(".workspace");
  if (workspace) workspace.style.setProperty("--chat-width", `${next}px`);
  return next;
}

function applySideWidth(width) {
  const next = Math.round(Math.min(SIDE_WIDTH.max, Math.max(SIDE_WIDTH.icon, width)));
  const workspace = document.querySelector(".workspace");
  if (workspace) workspace.style.setProperty("--side-width", `${next}px`);
  return next;
}

function profileMeta() {
  if (state.role === "admin") return { name: "합성 관리자", detail: "컴퓨터공학과", initial: "관" };
  const name = state.account ? state.account.name : "정민서";
  const dept = currentDepartment();
  const inst = currentInstitution();
  let detail = "학교 미연결";
  if (dept && hasOfficialAudit()) detail = `${state.account.year}학번 · ${dept.name}`;
  else if (dept) detail = dept.name;
  else if (state.account && state.account.departmentNote) detail = state.account.departmentNote;
  else if (inst) detail = inst.name;
  return { name, detail, initial: name.slice(0, 1) };
}

function shell(body) {
  const nav = (state.role === "student" ? STUDENT_NAV : ADMIN_NAV).map(([id, label, phase]) => `
      <button type="button" data-action="nav" data-screen="${id}" title="${esc(label)}" ${state.screen === id ? 'aria-current="page"' : ""}>
      <span class="nav-icon">${NAV_ICONS[id] || ""}</span>
      <span class="nav-copy"><strong>${label}</strong>${phase ? `<small>${phase}</small>` : ""}</span>
    </button>`).join("");
  const profile = profileMeta();
  return `<div class="workspace" style="--chat-width: ${state.chatWidth}px; --side-width: ${sideWidthNow()}px">
    <aside class="side${state.sideOpen ? "" : " is-icons"}">
      <button type="button" class="side-resize" data-resize="side" aria-label="탐색 너비 조절" title="끌어 너비를 바꿉니다. 두 번 누르면 기본 너비로 돌아갑니다."></button>
      <div class="brand">
        <div class="mark" aria-hidden="true">
          <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
            <path d="M3.5 4.2h4.4c.6 0 1.2.4 1.6.9.4-.5 1-.9 1.6-.9h4.4V13.8h-4.4c-.6 0-1.2.3-1.6.7-.4-.4-1-.7-1.6-.7H3.5V4.2Z" stroke="#f7f5f2" stroke-width="1.3" stroke-linejoin="round"/>
          </svg>
        </div>
        <div class="brand-copy">
          <div class="brand-name">UniversityPath</div>
          <div class="brand-sub">화면 목업</div>
        </div>
        <button type="button" class="ghost side-fold" data-action="toggle-side" title="${state.sideOpen ? "탐색을 아이콘만 남깁니다" : "탐색을 펼칩니다"}">${state.sideOpen ? "‹" : "›"}</button>
      </div>
      <nav class="nav" aria-label="주요 화면">${nav}</nav>
      <div class="side-account">
        <button type="button" data-action="nav" data-screen="settings" title="설정" ${state.screen === "settings" ? 'aria-current="page"' : ""}>
          <span class="nav-icon">${NAV_ICONS.settings}</span>
          <span class="nav-copy"><strong>설정</strong></span>
        </button>
        <button type="button" class="who-block" data-action="nav" data-screen="settings" title="${esc(profile.name)} · ${esc(profile.detail)}">
          <div class="avatar">${esc(profile.initial)}</div>
          <div class="who-copy">
            <b>${esc(profile.name)}</b>
            <p>${esc(profile.detail)}</p>
          </div>
        </button>
      </div>
    </aside>
    <section class="main">
      <header class="top">
        <div class="crumb">UniversityPath <b>화면 목업</b></div>
        ${state.role === "student" && state.screen === "graduation" ? `<div class="top-mock-tools">
          <button type="button" class="mock-tools-toggle" data-action="toggle-mock-tools" aria-expanded="${state.mockToolsOpen}" aria-label="목업 제어 열기" title="목업 제어">
            <svg width="17" height="17" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16M8 5v4M16 10v4M11 15v4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>
          </button>
          ${state.mockToolsOpen ? `<div class="mock-tools-popover" role="dialog" aria-label="목업 제어">
            <small>목업 전용</small>
            <b>졸업 규정 예시</b>
            <button type="button" data-action="audit-preview" data-preview="kd" aria-pressed="${state.auditPreview === "kd"}">경동대 · 실제 범위</button>
            <button type="button" data-action="audit-preview" data-preview="kookmin" aria-pressed="${state.auditPreview === "kookmin"}">국민대 · 비교 예시</button>
          </div>` : ""}
        </div>` : ""}
      </header>
      <div class="content">${body}</div>
    </section>
    ${state.role === "student" && state.chatOpen ? unifiedChatDock() : ""}
    </div>
    ${state.role === "student" && !state.chatOpen ? chatFab() : ""}
    ${viewerLayer()}`;
}

function findInstitution(id) {
  return INSTITUTIONS.find((item) => item.id === id) || null;
}

function findDepartment(id) {
  if (!id) return null;
  for (const inst of INSTITUTIONS) {
    const dept = inst.departments.find((item) => item.id === id);
    if (dept) return { ...dept, institution: inst.name, institutionId: inst.id };
  }
  return null;
}

function currentInstitution() {
  if (!state.account || !state.account.institutionId) return null;
  return findInstitution(state.account.institutionId);
}

function currentDepartment() {
  if (!state.account) return null;
  return findDepartment(state.account.departmentId);
}

function searchHits(kind) {
  const query = (kind.startsWith("link") ? state.linkDraft : state.authDraft)[kind.endsWith("school") ? "schoolQuery" : "deptQuery"].trim();
  if (!query) return [];
  if (kind.endsWith("school")) {
    const selected = findInstitution(kind === "auth-school" ? state.authDraft.institutionId : state.account && state.account.institutionId);
    if (selected && selected.name === query) return [];
    return INSTITUTIONS.filter((item) => item.name.includes(query));
  }
  const institutionId = kind === "auth-dept"
    ? state.authDraft.institutionId
    : state.account && state.account.institutionId;
  const inst = findInstitution(institutionId);
  if (!inst) return [];
  const selectedId = kind === "auth-dept" ? state.authDraft.departmentId : state.account.departmentId;
  const selected = findDepartment(selectedId);
  if (selected && selected.name === query) return [];
  return inst.departments.filter((item) => item.name.includes(query));
}

function searchResultHtml(kind) {
  const draft = kind.startsWith("link") ? state.linkDraft : state.authDraft;
  const query = (kind.endsWith("school") ? draft.schoolQuery : draft.deptQuery).trim();
  if (!query) return "";
  const chosenId = kind.endsWith("school")
    ? (kind === "auth-school" ? state.authDraft.institutionId : state.account && state.account.institutionId)
    : (kind === "auth-dept" ? state.authDraft.departmentId : state.account && state.account.departmentId);
  const chosen = kind.endsWith("school") ? findInstitution(chosenId) : findDepartment(chosenId);
  if (chosen && chosen.name === query) return "";
  const hits = searchHits(kind);
  if (!hits.length) return `<p class="disclaimer">해당하는 항목이 없습니다.</p>`;
  const action = `pick-${kind}`;
  return hits.map((item) => {
    const extra = item.departments
      ? (item.departments.length ? "등록 학과 있음" : "등록 학과 없음")
      : (item.rules ? "공식 규칙 있음" : "공식 규칙 없음");
    return `<button type="button" data-action="${action}" data-id="${item.id}">${esc(item.name)} · ${extra}</button>`;
  }).join("");
}

function hasOfficialAudit() {
  const dept = currentDepartment();
  return Boolean(dept && dept.rules && state.account && state.account.year === "2024");
}

function setsInScope(scope) {
  return RULE_SETS.filter((item) => item.scope === scope);
}

function selectedSetIds() {
  const filter = state.auditFilter || "institution";
  if (filter.startsWith("set:")) return [filter.slice(4)];
  return setsInScope(filter).map((item) => item.id);
}

function scopeRollup(scope) {
  const sets = setsInScope(scope);
  if (!sets.length) return "empty";
  if (sets.some((item) => item.status === "not_satisfied")) return "not_satisfied";
  if (sets.some((item) => item.status === "needs_review")) return "needs_review";
  if (sets.every((item) => item.status === "satisfied")) return "satisfied";
  return "needs_review";
}

function ruleScopeBar() {
  const filter = state.auditFilter || "institution";
  const pills = RULE_SCOPES.map((scope) => {
    const sets = setsInScope(scope.id);
    return `<button type="button" class="scope-pill" data-action="audit-filter" data-filter="${scope.id}" aria-pressed="${filter === scope.id}" title="${esc(scope.hint)}">
        <span>
          <b>${scope.label}</b>
          <small>${scope.hint}</small>
        </span>
        <strong class="count">${sets.length}</strong>
        ${stamp(scopeRollup(scope.id))}
      </button>`;
  }).join("");
  const openScope = RULE_SCOPES.find((scope) => scope.id === filter);
  const listed = openScope
    ? setsInScope(openScope.id)
    : filter.startsWith("set:")
      ? RULE_SETS.filter((item) => item.id === filter.slice(4))
      : [];
  const list = openScope || filter.startsWith("set:")
    ? `<div class="set-list" role="list">
        ${listed.length
          ? listed.map((item) => `<button type="button" class="set-row" data-action="audit-set" data-id="${item.id}" aria-pressed="${filter === `set:${item.id}`}" role="listitem">
              <span><b>${esc(item.name)}</b><small>${esc(item.range)} · 규칙 ${item.ruleCount}개</small></span>
              ${stamp(item.status)}
            </button>`).join("")
          : `<p class="disclaimer">이 계층에 선택된 규칙 묶음이 없습니다. 엔진은 이 계층을 건너뛰고 판정하지 않습니다.</p>`}
      </div>`
    : "";
  return `<section class="rule-bar">
      <div class="rule-bar-head">
        <div>
          <h2>기준 선택</h2>
          <p class="disclaimer">대학 공통 기준부터 봅니다. 탭을 누르면 해당 기준의 상세 표로 전환됩니다.</p>
        </div>
      </div>
      <div class="scope-pills" role="group" aria-label="규칙 계층">${pills}</div>
      ${list}
    </section>`;
}

function auditScreen() {
  if (!hasOfficialAudit()) {
    const dept = currentDepartment();
    const inst = currentInstitution();
    const explain = !inst && !dept
      ? "학교와 학과가 없어 공식 졸업 규칙을 적용하지 않습니다. 활동·자격과 채용 비교는 그대로 쓸 수 있습니다."
      : !dept
        ? `${inst.name}는 연결되어 있습니다. 학과 식별자가 비어 있어 공식 규칙을 고르지 않습니다. 직접 적은 이름으로는 범위를 추정하지 않습니다.`
        : dept.rules
          ? `${dept.institution} ${dept.name} 규칙은 이 학과 식별자에 있습니다. ${state.account.year ? "이 목업의 취득학점 예시는 2024학번만 있어, 다른 입학연도는 판정하지 않습니다." : "입학연도가 없어 교육과정을 고르지 않았고, 졸업 여부를 판정하지 않습니다."}`
          : `${dept.institution} ${dept.name} 레코드는 연결되어 있습니다. 공식 졸업 규칙은 아직 없어 판정하지 않습니다.`;
    return `<section class="card fill-card">
      <h2>졸업 감사</h2>
      <div class="verdict-top">
        <div>
          <div class="kicker">최종 상태</div>
          <div class="score">—</div>
        </div>
        ${stamp("not_applicable")}
      </div>
      <p class="explain">${explain}</p>
      ${inst || dept || (state.account && state.account.departmentNote) ? `<div class="row-card" style="margin-top:12px">
        <span class="tag">참고</span>
        <div><b>직접 적어 둔 목표 130학점</b><p>공식 GraduationRuleSet이 아닙니다. 이후 공식 규칙이 생겨도 이 메모는 지우지 않고, 공식 감사에는 넣지 않습니다.</p></div>
        ${stamp("not_applicable")}
      </div>` : ""}
    </section>`;
  }

  return `<div class="audit-pane">
    <div class="banner">초안입니다. 이 화면의 판정을 실제 졸업 사정으로 쓰지 않습니다.</div>
    ${state.auditPreview === "kookmin" ? kookminPreview() : kdAuditContent()}
  </div>`;
}

function kdAuditContent() {
  return `${ruleScopeBar()}
    ${commonDegreeRulesTable()}
    ${blendedCreditTable()}
    ${departmentRulesTable()}
    <section class="card audit-explain">
      <h2>설명</h2>
      <p class="explain" style="margin-top:0">학교 시스템의 확정 학사 기록으로 판정한 결과입니다. 학교에 등록되지 않은 과목·활동·자격이 있다면 먼저 학교 시스템에서 상태를 확인해 주세요.</p>
      <div class="meta-row">
        <span class="chip">취득학점 출처 · 학교 화면</span>
        <span class="chip">학과 인증 · 졸업인증요건 PDF</span>
        <span class="chip">LLM 설명</span>
      </div>
    </section>`;
}

function graduationOverview() {
  return `<section class="card graduation-overview">
    <div class="verdict-top">
      <div><p class="kicker">현재 졸업 준비 현황</p><h2>아직 충족되지 않은 기준이 있습니다.</h2><p class="disclaimer">학교 시스템의 확정 학사·승인 기록과 현재 적용 규정을 기준으로 자동 계산한 결과입니다.</p></div>
      <div class="head-verdict"><div class="score">88<span>/ 120</span></div>${stamp("not_satisfied")}</div>
    </div>
    <div class="overview-rule-grid">
      <div class="overview-rule"><span class="tag">대학 공통</span><div><b>최소 총 취득학점</b><p>120학점 중 88학점 · 32학점 부족</p></div>${stamp("not_satisfied")}</div>
      <div class="overview-rule"><span class="tag">내 교육과정</span><div><b>교양·전공·자유선택 학점</b><p>자유선택 14 / 23학점 · 나머지 항목은 확인 필요</p></div>${stamp("not_satisfied")}</div>
      <div class="overview-rule"><span class="tag">학과 기준</span><div><b>창의영역·전공영역 졸업인증</b><p>창의영역은 충족 · 전공영역은 공식 확인 필요</p></div>${stamp("needs_review")}</div>
    </div>
  </section>`;
}

function commonDegreeRulesTable() {
  const activeIds = new Set(selectedSetIds());
  if (!activeIds.has("set-kd-common-degree")) return "";
  return `<section class="card">
    <h2>대학 공통 기준</h2>
    <p class="disclaimer">이 묶음은 경동대학교 일반 학부생에 공통으로 적용되는 기준입니다. 편입·외국인·조기졸업 등 예외는 개인 적용 조건에서 추가됩니다.</p>
    <div class="table-wrap" style="margin-top:8px"><table class="data">
      <thead><tr><th>요건</th><th>현재 상태</th><th>판정</th><th>근거</th></tr></thead>
      <tbody>${COMMON_DEGREE_RULES.map((rule) => `<tr><td><b>${esc(rule.title)}</b><div style="color:var(--muted);font-size:12px;margin-top:3px">${esc(rule.note)}</div></td><td>${esc(rule.value)}</td><td>${stamp(rule.status)}</td><td><small>${esc(rule.source)}</small></td></tr>`).join("")}</tbody>
    </table></div>
  </section>`;
}

function kookminPreview() {
  return `<section class="card audit-explain"><h2>다른 대학 구조 미리보기</h2><p class="disclaimer">국민대학교 기업경영전공 2021학번 공식 졸업요건입니다. 경동대와 같은 학점 표를 쓰되, 이 학교에 필요한 교과영역 열만 구성한 예시입니다. 개인 성적은 연결하지 않아 판정하지 않습니다.</p></section>
    <section class="card fill-card"><h2>2021학번 교육과정 학점 현황</h2><p class="disclaimer">관리자는 학교별로 필요한 영역과 상한 조건만 등록합니다. 충족 판정은 대학 공통·전공 선택 요건 묶음에서 확인합니다.</p>
      <div class="table-wrap" style="margin-top:8px"><table class="data scrape kookmin-credits"><thead><tr><th rowspan="2">구분</th><th rowspan="2">총학점</th><th class="group" colspan="3">교양</th><th rowspan="2">전공선택</th><th rowspan="2">일반선택</th></tr><tr><th>기초</th><th>핵심</th><th>자유</th></tr></thead><tbody>
        <tr class="term-row"><td>졸업기준</td><td class="num">120</td><td class="num">8</td><td class="num">15</td><td class="num">2</td><td class="num">87</td><td class="num">8</td></tr>
        <tr><td>취득학점</td><td class="num blank">—</td><td class="num blank">—</td><td class="num blank">—</td><td class="num blank">—</td><td class="num blank">—</td><td class="num blank">—</td></tr>
      </tbody></table></div>
      <div class="detail-box" style="margin-top:12px">추가 조건 · 교양은 최대 50학점, 사제동행세미나는 재학 중 최대 4학점입니다. 핵심교양은 5개 영역에서 각 3학점 이상 이수합니다.</div>
    </section>
    <section class="card"><h2>전공 선택 요건</h2><p class="disclaimer">심화전공 또는 다·부전공 중 택 1 이수합니다. 대학·학부(과) 인증은 이 기준에서 미시행이므로 별도 빈 카드로 만들지 않습니다.</p><div class="row-card" style="margin-top:10px"><span class="tag">전공/다전공</span><div><b>심화전공 또는 다·부전공</b><p>택 1 이수</p></div>${stamp("needs_review")}</div></section>`;
}

function affiliationCard() {
  const dept = currentDepartment();
  const inst = currentInstitution();
  if (dept) {
    const note = state.account.departmentNote
      ? `<p class="disclaimer">직접 적어 둔 “${esc(state.account.departmentNote)}”는 공식 연결에 쓰이지 않습니다.</p>`
      : "";
    const yearField = dept.rules && !hasOfficialAudit()
      ? `<form class="connect-form" data-action="save-year">
          <label>입학연도<select data-store="yearDraft" data-field="year">
            <option value="" ${state.yearDraft.year ? "" : "selected"}>아직 없음</option>
            ${["2024", "2021", "2020", "2019"].map((year) => `<option value="${year}" ${state.yearDraft.year === year ? "selected" : ""}>${year}</option>`).join("")}
          </select></label>
          <button class="primary" type="submit">교육과정 연결</button>
        </form>
        <p class="disclaimer">졸업 규칙을 고를 때만 입학연도가 필요합니다. 재학 중이 아니면 비워 둡니다. 이 목업의 감사 예시는 2024년입니다.</p>`
      : "";
    return `<section class="card connect-bar">
      <h2>학과 연결</h2>
      <p><b>${esc(dept.institution)} ${esc(dept.name)}</b></p>
      <p class="disclaimer">공식 학과 값은 식별자 <code>${esc(dept.id)}</code>입니다. ${dept.rules ? "규칙은 이 식별자에 붙어 있습니다." : "공식 규칙이 이 식별자에 등록되면 학생 레코드를 하나씩 고치지 않습니다."}</p>
      ${note}
      ${yearField}
    </section>`;
  }
  const schoolSearch = inst ? "" : `<label>학교 검색<input data-search="link-school" data-store="linkDraft" data-field="schoolQuery" value="${esc(state.linkDraft.schoolQuery)}" placeholder="학교 이름" /></label>
    <div class="search-results" data-results="link-school">${searchResultHtml("link-school")}</div>`;
  const deptSearch = inst && inst.departments.length
    ? `<label>학과 검색<input data-search="link-dept" data-store="linkDraft" data-field="deptQuery" value="${esc(state.linkDraft.deptQuery)}" placeholder="학과 이름" /></label>
      <div class="search-results" data-results="link-dept">${searchResultHtml("link-dept")}</div>
      <p class="disclaimer">검색 결과에서 고르면 그 학과 식별자로 연결됩니다. 직접 적은 이름과 맞춰 보지 않습니다.</p>`
    : `<p class="disclaimer">${inst ? "이 학교에는 아직 등록된 학과가 없습니다." : "학교를 연결한 뒤에 학과를 검색합니다."} 지금은 직접 적어 두고, 학과가 등록되면 검색으로 연결합니다.</p>`;
  const note = state.account && state.account.departmentNote
    ? `<p>직접 기록 · ${esc(state.account.departmentNote)}</p>`
    : "";
  return `<section class="card connect-bar">
    <h2>학과</h2>
    <p class="disclaimer">공식 학과 식별자는 비어 있습니다. 직접 적은 이름은 화면에만 두고, 나중 연결에는 쓰이지 않습니다.</p>
    ${note}
    <form class="connect-form" data-action="save-note">
      <label>직접 적기<input data-store="noteDraft" data-field="text" value="${esc(state.noteDraft.text)}" placeholder="학과 이름" /></label>
      <button class="primary" type="submit">기록</button>
    </form>
    <div class="stack" style="margin-top:14px">
      ${schoolSearch}
      ${deptSearch}
    </div>
  </section>`;
}

function scrapeCell(value, tone) {
  if (value == null || value === "") return `<td class="num blank">—</td>`;
  return `<td class="num${tone ? ` ${tone}` : ""}">${esc(value)}</td>`;
}

function creditLine(id) {
  return CREDIT_LINES.find((line) => line.id === id) || DEPT_RULES.find((line) => line.id === id);
}

function findDoc(key) {
  return key === "cert" ? CERT_DOC : DOC;
}

function portalValue(source, key) {
  return Object.prototype.hasOwnProperty.call(source, key) ? source[key] : "";
}

function blendedCreditTable() {
  if (!hasOfficialAudit()) return "";
  const activeIds = new Set(selectedSetIds());
  if (!activeIds.size) {
    return `<section class="card fill-card">
      <h2>규칙 엔진 판정</h2>
      <p class="disclaimer">이 범위에 넣을 공식 규칙 묶음이 없어 엔진이 판정하지 않습니다. 다른 계층을 고르거나 전체를 보면 있는 묶음의 결과만 나옵니다.</p>
    </section>`;
  }
  if (!activeIds.has("set-kd-cs-min")) return "";
  const applied = { total: 0 };
  PORTAL_COLS.forEach((col) => { applied[col.key] = 0; });
  state.registrations.filter((row) => row.term === CURRENT_TERM).forEach((row) => {
    const credits = Number(row.credits) || 0;
    applied.total += credits;
    const key = REG_TO_PORTAL[row.category];
    if (key) applied[key] += credits;
  });
  const cols = PORTAL_COLS;
  const ruleName = (col) => {
    const line = col.rule ? creditLine(col.rule) : null;
    return line ? line.title : "—";
  };
  const numberRow = (label, source, toneFor) => `<tr>
      <th scope="row">${label}</th>
      ${cols.map((col) => {
        const value = col.key === "volunteer" && label === "신청학점"
          ? "—"
          : (label === "신청학점" ? String(applied[col.key] || 0) : portalValue(source, col.key));
        return scrapeCell(value, toneFor ? toneFor(col.key, value) : "");
      }).join("")}
    </tr>`;
  return `<section class="card fill-card">
      <h2>내 교육과정 학점 현황</h2>
      <p class="disclaimer">학교 화면의 학점 항목과 적용 교육과정 기준을 나란히 보여줍니다. 충족 판정은 위의 대학 공통 기준과 아래 학과 졸업인증 기준에서 확인합니다.</p>
      <div class="table-wrap" style="margin-top:8px">
        <table class="data scrape">
          <thead>
            <tr>
              <th rowspan="3">구분</th>
              <th rowspan="3">총학점</th>
              <th rowspan="3">사회봉사</th>
              <th class="group" colspan="6">교양</th>
              <th class="group" colspan="2">전공</th>
              <th rowspan="3">자유</th>
              <th rowspan="3">교직</th>
              <th rowspan="3">복수</th>
              <th rowspan="3">부전</th>
            </tr>
            <tr>
              ${PORTAL_COLS.filter((col) => col.key !== "total" && col.key !== "volunteer" && col.key !== "free" && col.key !== "teaching" && col.key !== "doubleMajor" && col.key !== "minor").map((col) => `<th>${col.label}</th>`).join("")}
            </tr>
            <tr class="rule-names">
              ${cols.filter((col) => !["total", "volunteer", "free", "teaching", "doubleMajor", "minor"].includes(col.key)).map((col) => `<th>${esc(ruleName(col))}</th>`).join("")}
            </tr>
          </thead>
          <tbody>
            ${numberRow("졸업기준", SCHOOL_STANDARD)}
            ${numberRow("취득학점", SCHOOL_EARNED)}
            ${numberRow("신청학점", applied)}
            ${numberRow("부족학점", SCHOOL_SHORT, (key, value) => (Number(value) > 0 ? "short" : ""))}
          </tbody>
        </table>
      </div>
    </section>`;
}

function departmentRulesTable() {
  if (!hasOfficialAudit()) return "";
  const activeIds = new Set(selectedSetIds());
  if (!activeIds.has("set-kd-cs-cert")) return "";
  return `<section class="card">
      <h2>규칙 엔진 판정 · 학과 졸업인증</h2>
      <p class="disclaimer">경동대학교 컴퓨터공학과 졸업인증요건 PDF 초안입니다. 창의영역 택 1과 전공영역 택 1을 함께 충족해야 합니다. 택 1 안에서는 한 경로만 채우면 됩니다.</p>
      <div class="table-wrap" style="margin-top:8px">
        <table class="data">
          <thead><tr><th>묶음</th><th>규칙</th><th>상태</th></tr></thead>
          <tbody>
            ${DEPT_RULES.map((line) => `<tr>
              <td>${esc(line.group)}</td>
              <td><b>${esc(line.title)}</b></td>
              <td>${stamp(line.status)}</td>
            </tr>`).join("")}
          </tbody>
        </table>
      </div>
    </section>`;
}

function recordsScreen() {
  const visible = state.registrations.filter((row) => {
    if (state.regFilter === "current") return row.term === CURRENT_TERM;
    if (state.regFilter === "past") return row.term !== CURRENT_TERM;
    return true;
  }).slice().sort((a, b) => b.term.localeCompare(a.term) || a.title.localeCompare(b.title, "ko"));
  const terms = [...new Set(visible.map((row) => row.term))];
  const draft = state.regDraft;
  const categoryOptions = REG_CATEGORIES.map((category) =>
    `<option value="${category}" ${draft.category === category ? "selected" : ""}>${category}</option>`).join("");
  const body = terms.map((term) => {
    const rows = visible.filter((row) => row.term === term);
    const label = term === CURRENT_TERM ? `${term} · 이번 학기 계획` : `${term} · 과거 계획`;
    return `<tr class="term-row"><td colspan="5">${label} · ${rows.reduce((sum, row) => sum + Number(row.credits), 0)}학점</td></tr>`
      + rows.map((row) => `<tr class="${row.term === CURRENT_TERM ? "is-hit" : ""}">
        <td>${esc(row.title)}</td>
        <td>${esc(row.category)}</td>
        <td>${esc(row.section || "—")}</td>
        <td class="num">${esc(row.credits)}</td>
        <td><button type="button" class="ghost" data-action="remove-reg" data-id="${esc(row.id)}">빼기</button></td>
      </tr>`).join("");
  }).join("");

  return `<section class="card fill-card">
      <h2>수강 계획·보조 기록</h2>
      <p class="disclaimer">학교 수강·성적 시스템을 먼저 확인해 주세요. 이 화면에는 다음 학기 계획과 함께 확인할 내용을 정리할 수 있습니다.</p>
      <form class="reg-form" data-action="add-registration">
        <label>계획 학기<input name="term" data-store="regDraft" data-field="term" value="${esc(draft.term)}" /></label>
        <label class="grow">과목명<input name="title" data-store="regDraft" data-field="title" value="${esc(draft.title)}" placeholder="글쓰기" /></label>
        <label>이수구분<select name="category" data-store="regDraft" data-field="category">${categoryOptions}</select></label>
        <label>학점<input name="credits" data-store="regDraft" data-field="credits" inputmode="decimal" value="${esc(draft.credits)}" /></label>
        <label>분반<input name="section" data-store="regDraft" data-field="section" value="${esc(draft.section)}" /></label>
        <button class="primary" type="submit">계획 추가</button>
      </form>
      ${state.regError ? `<p class="disclaimer" style="color:var(--bad)">${esc(state.regError)}</p>` : ""}
      <div class="filters" role="group" aria-label="신청 범위" style="margin-top:10px">
        ${[["all", "전체"], ["current", "이번 학기"], ["past", "과거 계획"]].map(([id, label]) =>
          `<button type="button" data-action="reg-filter" data-filter="${id}" aria-pressed="${state.regFilter === id}">${label}</button>`).join("")}
      </div>
      <div class="table-wrap" style="margin-top:10px">
        <table class="data">
          <thead><tr><th>과목</th><th>이수구분</th><th>분반</th><th class="num">학점</th><th></th></tr></thead>
          <tbody>
            ${body || `<tr><td colspan="5">이 범위의 계획 기록이 없습니다.</td></tr>`}
          </tbody>
        </table>
      </div>
    </section>`;
}

function entryList(rows, action, renderRow) {
  if (!rows.length) return `<p class="disclaimer">아직 없습니다. 위 칸에 넣고 추가를 누르세요.</p>`;
  return `<div class="stack fill-list">${rows.map((row) => `<div class="entry-row">
      <div>${renderRow(row)}</div>
      <button type="button" class="ghost" data-action="${action}" data-id="${esc(row.id)}">빼기</button>
    </div>`).join("")}</div>`;
}

function activitiesScreen(mode = "activities") {
  if (mode === "portfolio") return portfolioScreen();
  const volunteer = state.volunteerDraft;
  const experience = state.experienceDraft;
  const certificate = state.certificateDraft;
  const volunteerHours = state.volunteers.reduce((sum, row) => sum + Number(row.hours), 0);
  const typeOptions = ["프로젝트", "동아리", "공모전", "인턴", "아르바이트", "기타"].map((type) =>
    `<option value="${type}" ${experience.type === type ? "selected" : ""}>${type}</option>`).join("");
  const screenMeta = {
    activities: ["활동", "학교 시스템에 등록·승인한 활동을 보조 기록으로 정리하고, 다음 활동을 찾아보세요."],
    experiences: ["경험", "프로젝트, 동아리, 인턴, 아르바이트 경험을 시간 순서대로 쌓아보세요."],
    credentials: ["자격", "필요한 자격과 일정은 Q-Net에서 확인하고, 학교 또는 채용에 등록·확인된 자격만 여기에 정리해 주세요."],
  };
  const [title, lede] = screenMeta[mode] || screenMeta.activities;
  return `<header class="page-head">
      <div>
        <p class="kicker">활동 기록</p>
        <h1>${title}</h1>
        <p class="lede">${lede}</p>
      </div>
    </header>
    <div class="activity-grid is-${mode}">
    <section class="card volunteer-card">
      <div class="section-title-row"><div><h2>봉사 보조 기록</h2><p class="disclaimer">학교 시스템에 등록하고 승인된 봉사 활동을 여기에도 정리합니다. 현재 보조 기록 합계는 ${volunteerHours}시간입니다.</p></div><a class="external-link" href="https://www.1365.go.kr/" target="_blank" rel="noopener noreferrer" title="새 탭에서 1365 자원봉사포털 열기">1365 봉사 찾기 ↗</a></div>
      <p class="disclaimer volunteer-link-note">1365에서 활동을 찾아 직접 신청한 뒤 학교에 등록하세요. 이곳에는 <b>학교에서 승인된 봉사활동만 등록해 주세요.</b></p>
      <form class="entry-form volunteer-form" data-action="add-volunteer">
        <label class="grow">내용<input data-store="volunteerDraft" data-field="title" value="${esc(volunteer.title)}" placeholder="교내 봉사" /></label>
        <label>승인 시간<input data-store="volunteerDraft" data-field="hours" inputmode="decimal" value="${esc(volunteer.hours)}" placeholder="학교 승인 시간" /></label>
        <button class="primary" type="submit">봉사 추가</button>
      </form>
      ${state.volunteerError ? `<p class="disclaimer" style="color:var(--bad)">${esc(state.volunteerError)}</p>` : ""}
      ${entryList(state.volunteers, "remove-volunteer", (row) => `<b>${esc(row.title)}</b><p>학교 승인 ${esc(row.hours)}시간 · UniversityPath 보조 기록</p>`)}
    </section>
    <section class="card experience-card">
      <h2>경험</h2>
      <form class="entry-form experience-form" data-action="add-experience">
        <label>종류<select data-store="experienceDraft" data-field="type">${typeOptions}</select></label>
        <label class="grow">제목<input data-store="experienceDraft" data-field="title" value="${esc(experience.title)}" placeholder="축제 운영" /></label>
        <label>기관<input data-store="experienceDraft" data-field="organization" value="${esc(experience.organization)}" placeholder="동아리, 회사" /></label>
        <label>시작<input data-store="experienceDraft" data-field="started" type="date" value="${esc(experience.started)}" /></label>
        <label>종료<input data-store="experienceDraft" data-field="ended" type="date" value="${esc(experience.ended)}" /></label>
        <button class="primary" type="submit">경험 추가</button>
      </form>
      <p class="disclaimer">종료일을 비우면 진행 중으로 둡니다.</p>
      ${state.experienceError ? `<p class="disclaimer" style="color:var(--bad)">${esc(state.experienceError)}</p>` : ""}
      ${entryList(state.experiences, "remove-experience", (row) => `<b>${esc(row.title)}</b><p>${esc(row.type)} · ${esc(row.organization || "기관 없음")} · ${esc(row.started || "시작일 없음")}–${row.ended ? esc(row.ended) : "진행 중"}</p>`)}
    </section>
    <section class="card certificate-card">
      <div class="section-title-row"><div><h2>보유 자격</h2><p class="disclaimer">학교 또는 채용에서 확인된 자격만 등록해 주세요.</p></div></div>
      <form class="entry-form certificate-form" data-action="add-certificate">
        <label class="grow">이름<input data-store="certificateDraft" data-field="name" value="${esc(certificate.name)}" placeholder="TOEIC" /></label>
        <label>점수·등급<input data-store="certificateDraft" data-field="detail" value="${esc(certificate.detail)}" placeholder="850" /></label>
        <label>취득일<input data-store="certificateDraft" data-field="earned" type="date" value="${esc(certificate.earned)}" /></label>
        <button class="primary" type="submit">자격 추가</button>
      </form>
      <p class="disclaimer">준비가 필요한 자격과 일정은 오른쪽 AI 대화에서 계획으로 정리하세요. 자격 번호는 받지 않습니다.</p>
      ${state.certificateError ? `<p class="disclaimer" style="color:var(--bad)">${esc(state.certificateError)}</p>` : ""}
      ${entryList(state.certificates, "remove-certificate", (row) => `<b>${esc(row.name)}</b><p>${esc(row.detail || "점수 없음")} · ${esc(row.earned || "취득일 없음")}</p>`)}
    </section>
    </div>`;
}

function portfolioScreen() {
  const work = state.workDraft;
  const kindOptions = ["프로젝트", "논문", "수상", "공모전", "기타"].map((kind) =>
    '<option value="' + kind + '" ' + (work.kind === kind ? "selected" : "") + '>' + kind + '</option>').join("");
  const pane = state.portfolioPane;
  const rows = entryList(state.works, "remove-work", (row) =>
    '<b>' + esc(row.title) + '</b><p>' + esc(row.kind) + ' · ' + esc(row.role || "역할 미입력") + ' · ' + esc(row.period || "기간 미입력") + '<br />' + esc(row.result || "결과 미입력") + (row.url ? ' · <a href="' + esc(row.url) + '" target="_blank" rel="noopener noreferrer">공개 링크 ↗</a>' : "") + '</p>');
  let content = "";
  if (pane === "records") {
    content = '<section class="card portfolio-work-card"><div class="section-title-row"><div><h2>성과 기록</h2><p class="disclaimer">파일 업로드는 필수가 아닙니다. 맡은 역할과 결과를 먼저 남기고, 공개 가능한 링크만 선택적으로 추가하세요.</p></div></div><form class="portfolio-entry-form" data-action="add-work"><label class="span-2">제목<input data-store="workDraft" data-field="title" value="' + esc(work.title) + '" placeholder="프로젝트 또는 논문 제목" /></label><label>종류<select data-store="workDraft" data-field="kind">' + kindOptions + '</select></label><label>기간<input data-store="workDraft" data-field="period" value="' + esc(work.period) + '" placeholder="2026.03–2026.06" /></label><label class="span-2">나의 역할<input data-store="workDraft" data-field="role" value="' + esc(work.role) + '" placeholder="기획, UI 설계, 백엔드 API 개발" /></label><label class="span-2">결과·성과<input data-store="workDraft" data-field="result" value="' + esc(work.result) + '" placeholder="시연 완료, 수상, 사용자 수, 개선 수치" /></label><label class="span-2">공개 링크 <small>선택</small><input data-store="workDraft" data-field="url" value="' + esc(work.url) + '" placeholder="https://github.com/... 또는 공개 페이지" /></label><button class="primary" type="submit">성과 기록 추가</button></form><p class="evidence-note">발표 PDF·이미지 같은 파일은 권한과 저장 정책이 정해진 뒤에만 선택 증빙으로 추가합니다. 지금은 이 화면에 올리지 않습니다.</p>' + (state.workError ? '<p class="disclaimer" style="color:var(--bad)">' + esc(state.workError) + '</p>' : "") + rows + '</section>';
  } else if (pane === "showcase") {
    const choices = state.works.map((row) => '<article><div><span class="stamp good">구성 후보</span><h3>' + esc(row.title) + '</h3><p>' + esc(row.kind) + ' · ' + esc(row.role || "역할 미입력") + ' · ' + esc(row.result || "결과 미입력") + '</p></div></article>').join("") || '<p class="disclaimer">먼저 성과 기록을 추가해 주세요.</p>';
    content = '<section class="card portfolio-work-card"><h2>포트폴리오 구성</h2><p class="lede compact">새 파일을 다시 올리는 곳이 아닙니다. 성과 기록 중 공개할 항목을 고르고 순서를 정하는 단계입니다.</p><div class="showcase-list">' + choices + '</div><p class="evidence-note">공개 가능 여부와 사실 관계는 사용자가 최종 확인합니다. AI는 목차와 설명 초안만 제안합니다.</p></section>';
  } else {
    content = '<section class="card portfolio-work-card"><h2>지원 문서</h2><p class="lede compact">이력서와 자기소개서는 성과 메타데이터가 아니라 지원처별로 다듬는 별도 문서입니다. 기록된 경험·성과를 골라 초안을 만들고, 최종 내용은 직접 검토합니다.</p><div class="application-empty"><div><span class="stamp neutral">아직 만든 문서 없음</span><h3>이력서 · 자기소개서</h3><p>지원할 직무와 선택한 성과를 바탕으로 사용자 편집 초안을 시작할 수 있습니다. 초안 작성은 오른쪽 AI 대화에서 시작하세요.</p></div></div>' + (state.applicationNotice ? '<p class="evidence-note">' + esc(state.applicationNotice) + '</p>' : "") + '</section>';
  }
  return '<header class="page-head"><div><p class="kicker">나의 결과물</p><h1>성과 기록과 지원 문서</h1><p class="lede">한 일을 사실 중심으로 기록한 뒤, 공개할 성과와 지원 문서를 따로 구성합니다.</p></div></header><nav class="portfolio-tabs" aria-label="포트폴리오 작업 단계"><button type="button" class="' + (pane === "records" ? "active" : "") + '" data-action="portfolio-pane" data-pane="records">1. 성과 기록</button><button type="button" class="' + (pane === "showcase" ? "active" : "") + '" data-action="portfolio-pane" data-pane="showcase">2. 포트폴리오 구성</button><button type="button" class="' + (pane === "application" ? "active" : "") + '" data-action="portfolio-pane" data-pane="application">3. 지원 문서</button></nav><div class="portfolio-layout">' + content + '</div>';
}

function bandsForPage(page) {
  return BANDS.filter((band) => {
    if (page === 1) return band.page === "1";
    if (page === 2) return band.page === "1–2";
    return band.page === "3";
  });
}

function paperPage(page, cited, docKey = "credits") {
  if (docKey === "cert") return certPaperPage(page, cited);
  const bands = bandsForPage(page);
  const marked = cited.includes(page) && bands.some((band) => band.applied);
  const rows = bands.map((band) => `<tr class="${marked && band.applied ? "is-cited" : ""}">
      <td>${esc(band.years)}</td>
      <td>${esc(band.track)}${band.note ? `<div class="paper-note">${esc(band.note)}</div>` : ""}</td>
      <td>${esc(band.liberal)}</td>
      <td>${esc(band.major)}</td>
      <td>${esc(band.free)}</td>
      <td>${esc(band.total)}</td>
    </tr>`).join("");
  return `<article class="paper">
      <p class="paper-school">경동대학교 · 컴퓨터공학과</p>
      <h3>졸업 최소 이수학점</h3>
      <p class="paper-meta">2026학년도 · ${page}쪽</p>
      ${marked ? `<p class="paper-mark">이 답변이 집는 쪽</p>` : ""}
      <table>
        <thead><tr><th>입학</th><th>경로</th><th>교양</th><th>전공</th><th>자유</th><th>졸업</th></tr></thead>
        <tbody>${rows}</tbody>
      </table>
      <footer><span>초안</span><span>${page} / 3</span></footer>
    </article>`;
}

function certPaperPage(page, cited) {
  const marked = cited.includes(page);
  const mark = marked ? `<p class="paper-mark">이 답변이 집는 쪽</p>` : "";
  let body = "";
  if (page === 1) {
    body = `<ul class="paper-list">
        <li>졸업학점 120과 교과구분별 최소졸업이수학점을 충족한다.</li>
        <li>모든 필수 과목을 이수하고 P/F 과목은 합격한다.</li>
        <li>졸업작품 발표 또는 졸업시험 등 졸업실적 심사에 합격한다.</li>
        <li>일반 졸업자는 8학기 이상 등록한다.</li>
        <li>졸업인증제 자격을 취득한다. 창의영역 택 1 + 전공영역 택 1.</li>
        <li>별도로 학과가 정한 졸업인증 자격에 부합한다.</li>
        <li>계약학과 및 직장인 교과과정 대상자는 졸업인증제를 면제한다.</li>
      </ul>
      <table>
        <thead><tr><th>계열</th><th>학과</th><th>창의</th><th>전공</th><th>비고</th></tr></thead>
        <tbody>
          <tr class="${marked ? "is-cited" : ""}"><td>공학</td><td>컴퓨터공학과</td><td>○</td><td>○</td><td></td></tr>
          <tr><td></td><td>컴퓨터응용학과(계)</td><td></td><td></td><td>계약학과 면제</td></tr>
        </tbody>
      </table>`;
  } else if (page === 2) {
    body = `<p class="paper-meta">창의영역 택 1</p>
      <ul class="paper-list">
        <li>정보화: 워드프로세서 1급, 컴활 2급, ITQ B등급, MOS 등 중 택 1</li>
        <li class="${marked ? "is-cited-line" : ""}">세계화 기타계열: TOEIC 500, TOEFL 60, TEPS 530 등</li>
        <li>인성/봉사/리더십: 사회봉사 36시간 이상 등</li>
        <li>취∙창업: 관련 교과 5학점 또는 프로그램 3회 등</li>
      </ul>`;
  } else {
    body = `<p class="paper-meta">전공영역: 학과졸업인증제 I 또는 II 중 선택</p>
      <ul class="paper-list">
        <li>I 자격/면허: 정보처리기사·산업기사 등 1개 이상</li>
        <li>I 실무/실습: 현장실습 4주, IT 봉사 16시간, 비교과 70%, 전공필수 B0, 관련 교육 중 1개 이상</li>
        <li>II 취업: 4대보험 취업 또는 창업 증빙을 졸업사정 전까지 제출</li>
        <li>직장인 교과과정 이수자는 졸업인증 면제</li>
      </ul>`;
  }
  return `<article class="paper">
      <p class="paper-school">경동대학교 · 컴퓨터공학과</p>
      <h3>졸업자격요건</h3>
      <p class="paper-meta">${page}쪽</p>
      ${mark}
      ${body}
      <footer><span>초안</span><span>${page} / 3</span></footer>
    </article>`;
}

function sourceCard(cited = [], compact = false, docKey = "credits") {
  const doc = findDoc(docKey);
  const sorted = [...cited].sort((a, b) => a - b);
  const page = sorted.includes(2) ? 2 : (sorted[0] || 1);
  const span = sorted.length > 1 ? `${sorted[0]}–${sorted[sorted.length - 1]}쪽` : `${page}쪽`;
  const address = `${doc.file}#page=${page}`;
  return `<article class="source${compact ? " is-compact" : ""}">
      <b>${esc(doc.title)}</b>
      <p>${cited.length ? `근거 ${span}` : `문서 ${doc.pages}`} · 문서 식별자 <code>${doc.id}</code></p>
      <div class="shot">
        ${paperPage(page, cited, docKey)}
        <button type="button" class="shot-hit" data-action="open-doc" data-doc="${docKey}" data-page="${page}" data-cited="${cited.join(",")}" data-label="${page}쪽 열기" aria-label="${esc(doc.title)} ${page}쪽 열기"></button>
      </div>
      <button type="button" class="doc-url" data-action="open-doc" data-doc="${docKey}" data-page="${page}" data-cited="${cited.join(",")}">${esc(address)}</button>
      ${compact ? "" : `<p>공식 웹 주소는 아직 없습니다. 이 주소는 목업에서 해당 PDF 쪽을 엽니다.</p>
      <p>SHA-256 ${doc.hash.slice(0, 16)}… · 초안, 검토 필요</p>`}
    </article>`;
}

function viewerLayer() {
  if (!state.viewer) return "";
  const page = state.viewer.page;
  const cited = state.viewer.cited;
  const docKey = state.viewer.doc || "credits";
  const doc = findDoc(docKey);
  return `<div class="viewer">
      <button type="button" class="viewer-backdrop" data-action="close-doc" aria-label="닫기"></button>
      <div class="viewer-frame">
        <div class="viewer-bar">
          <div>
            <b>${esc(doc.title)}</b>
            <div class="viewer-url">${esc(doc.file)}#page=${page}</div>
          </div>
          <button type="button" class="ghost" data-action="close-doc">닫기</button>
        </div>
        <div class="viewer-stage">
          <button type="button" class="ghost" data-action="doc-page" data-page="${page - 1}" ${page <= 1 ? "disabled" : ""}>이전 쪽</button>
          ${paperPage(page, cited, docKey)}
          <button type="button" class="ghost" data-action="doc-page" data-page="${page + 1}" ${page >= 3 ? "disabled" : ""}>다음 쪽</button>
        </div>
        <p class="viewer-note">원문은 docs/sources에 있습니다. 보이는 쪽은 텍스트를 옮긴 초안입니다.</p>
      </div>
    </div>`;
}

function chatFab() {
  return `<button type="button" class="chat-fab" data-action="toggle-chat" aria-label="AI 대화 열기" title="AI 대화 열기">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M5.5 5.5h13v9.1H10l-4.5 3.4V5.5Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M9 10h6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
    </button>`;
}

function chatDock() {
  const thread = state.chat.map((item) => {
    if (item.pending) {
      return `<div class="bubble assistant"><div class="who-line">검색 중</div><div class="pending" aria-label="불러오는 중"><i></i><i></i><i></i></div></div>`;
    }
    if (item.role === "user") return `<div class="bubble user"><div class="who-line">질문</div>${esc(item.text)}</div>`;
    const badge = item.status ? stamp(item.status) : `<span class="stamp mute">안내</span>`;
    const cite = item.sources
      ? sourceCard(item.pages || [1], true, item.doc || "credits")
      : item.status === "insufficient_evidence"
        ? `<p class="disclaimer">근거 부족 상태에서는 출처 목록이 비어 있습니다. 빈 목록으로 문장을 채우지 않습니다.</p>`
        : "";
    return `<div class="bubble assistant"><div class="who-line">답변 ${badge}</div>${esc(item.text)}</div>${cite}`;
  }).join("");
  return `<aside class="chat-dock" aria-label="공식 문서 질의">
      <button type="button" class="chat-resize" data-resize="chat" aria-label="규정 질의 너비 조절" title="끌어 너비를 바꿉니다. 두 번 누르면 기본 너비로 돌아갑니다."></button>
      <div class="chat-head">
        <div>
          <p class="kicker">학교 규정</p>
          <h2>공식 문서 질의</h2>
        </div>
        <button type="button" class="chat-collapse" data-action="toggle-chat" aria-label="공식 문서 질의 접기" title="공식 문서 질의 접기">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m14.5 6-6 6 6 6" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></svg>
        </button>
      </div>
      <p class="chat-note">졸업·학사 규정의 공식 문서만 검색합니다. 판정은 규칙 엔진 결과를 설명할 뿐, 이 대화가 바꾸지 않습니다.</p>
      <div class="chat-thread">${thread}</div>
      <div class="chat-foot">
        <div class="prompts">
          <button type="button" data-action="ask" data-q="credits">2024학번 단일전공 졸업 학점</button>
          <button type="button" data-action="ask" data-q="cert">학과 졸업인증제</button>
          <button type="button" data-action="ask" data-q="eligibility">지금 졸업할 수 있나</button>
          <button type="button" data-action="ask" data-q="exchange">교환학생 인정 학점 상한</button>
        </div>
        <form class="composer" data-action="ask-submit">
          <input id="composer" name="q" placeholder="공식 규정을 질문해 보세요" value="${esc(state.draft)}" />
          <button class="primary" type="submit">보내기</button>
        </form>
      </div>
    </aside>`;
}

function unifiedChatDock() {
  const type = screenWorkspaceType();
  const meta = type ? WORKSPACE_META[type] : null;
  const isWork = Boolean(meta);
  const thread = state.chat.map((item) => {
    if (item.pending) return '<div class="bubble assistant"><div class="who-line">AI가 정리 중</div><div class="pending" aria-label="불러오는 중"><i></i><i></i><i></i></div></div>';
    if (item.role === "user") return '<div class="bubble user"><div class="who-line">나의 요청</div>' + esc(item.text) + '</div>';
    const label = item.workspace ? "AI 답변" : item.status ? "문서 근거 답변" : "AI 안내";
    const badge = item.status ? stamp(item.status) : '<span class="stamp mute">안내</span>';
    const cite = item.sources ? sourceCard(item.pages || [1], true, item.doc || "credits") : item.status === "insufficient_evidence" ? '<p class="disclaimer">근거 부족 상태에서는 출처를 꾸며내지 않습니다.</p>' : "";
    return '<div class="bubble assistant"><div class="who-line">' + label + ' ' + badge + '</div>' + esc(item.text) + '</div>' + cite;
  }).join("");
  const promptRows = "";
  const suggestions = isWork && state.workspace_type === type && state.suggested_actions.length
    ? '<section class="chat-suggestions"><p class="kicker">제안된 다음 단계</p>' + state.suggested_actions.map((item) => '<div><b>' + esc(item) + '</b><button type="button" class="ghost tiny" data-action="apply-workspace-draft">' + esc(meta.action) + '</button></div>').join("") + '</section>'
    : "";
  const qnet = type === "credential" && state.chat.some((item) => item.workspace === "credential")
    ? '<section class="chat-integration"><p class="kicker">Q-Net 연계 목업</p><b>필요 자격과 일정은 이 대화 결과에서만 안내합니다.</b><p>백엔드는 Q-Net 공용 API의 종목·응시자격·일정을 조회하고, 사용자는 학교 또는 채용에서 확인된 자격만 직접 기록합니다.</p><a class="external-link" href="https://www.q-net.or.kr/" target="_blank" rel="noopener noreferrer">Q-Net에서 확인 ↗</a></section>'
    : "";
  const context = isWork ? '현재 화면의 기록 · ' + workspaceContext(type) + ' · 질문 내용을 바탕으로 필요한 정보와 근거를 찾습니다.' : '현재 화면의 기록을 읽고 답합니다. 졸업·학사 규정 질문에는 공식 문서와 페이지 근거를 자동으로 붙입니다.';
  const title = "AI 도우미";
  const kicker = "RAG 기반 대화";
  const placeholder = "궁금한 점이나 정리할 일을 자연어로 물어보세요";
  return '<aside class="chat-dock unified-chat" aria-label="' + title + '"><button type="button" class="chat-resize" data-resize="chat" aria-label="AI 대화 너비 조절" title="끌어 너비를 바꿉니다."></button><div class="chat-head"><div><p class="kicker">' + esc(kicker) + '</p><h2>' + title + '</h2></div><div class="chat-head-actions"><button type="button" class="chat-collapse" data-action="toggle-chat" aria-label="AI 대화 접기" title="AI 대화 접기">‹</button></div></div><p class="chat-note">' + esc(context) + '</p><div class="chat-thread">' + thread + qnet + suggestions + '</div><div class="chat-foot"><div class="prompts">' + promptRows + '</div><form class="composer" data-action="unified-ai-submit"><input id="composer" name="q" placeholder="' + esc(placeholder) + '" value="' + esc(state.draft) + '" /><button class="primary" type="submit">보내기</button></form></div></aside>';
}

const WORKSPACE_META = {
  study: {
    eyebrow: "학업 RAG 작업 대화",
    title: "이번 학기 수강을 정리해볼까요?",
    description: "현재 신청 기록을 바탕으로 과목 인정 영역과 다음 학기 계획을 함께 살핍니다.",
    starter: "현재 신청 과목으로 부족한 영역을 채울 방법을 알려줘",
    action: "수강 계획 초안에 가져오기",
  },
  activity: {
    eyebrow: "활동 RAG 작업 대화",
    title: "활동 경험을 다음 기록으로 이어가볼까요?",
    description: "봉사·교내외 활동의 증빙 준비와 다음 활동 후보를 정리합니다.",
    starter: "내 활동 기록을 보고 다음에 준비할 것을 정리해줘",
    action: "활동 기록 초안에 가져오기",
  },
  experience: {
    eyebrow: "경험 RAG 작업 대화",
    title: "경험을 나의 강점으로 정리해볼까요?",
    description: "프로젝트, 동아리, 인턴 경험을 이력 문장과 확인할 자료로 정리합니다.",
    starter: "현재 경험을 이력에 쓸 수 있게 정리해줘",
    action: "경험 기록 초안에 가져오기",
  },
  credential: {
    eyebrow: "자격 RAG 작업 대화",
    title: "자격과 준비 목표를 찾아볼까요?",
    description: "학과 졸업인증과 채용 준비에서 부족한 자격을 찾고, Q-Net API로 가져온 종목·응시자격·일정을 바탕으로 준비 계획을 정리합니다.",
    starter: "학과와 채용에 필요한 자격의 준비 순서를 정리해줘",
    action: "자격 기록 초안에 가져오기",
  },
  portfolio: {
    eyebrow: "성과 RAG 작업 대화",
    title: "성과를 포트폴리오로 구성해볼까요?",
    description: "프로젝트·논문·수상 기록을 포트폴리오 구조와 보완 항목으로 정리합니다.",
    starter: "내 성과를 포트폴리오 목차로 정리해줘",
    action: "성과 기록 초안에 가져오기",
  },
  application: {
    eyebrow: "지원 문서 RAG 작업 대화",
    title: "지원할 곳에 맞춰 경험을 골라볼까요?",
    description: "기록된 경험과 성과를 골라 이력서·자기소개서의 사용자 편집 초안을 준비합니다.",
    starter: "백엔드 직무 지원용 자기소개서에 쓸 경험을 골라줘",
    action: "지원 문서 초안에 가져오기",
  },
  career: {
    eyebrow: "진로 RAG 작업 대화 · 2차",
    title: "관심 진로를 탐색해볼까요?",
    description: "공고를 평가하거나 합격을 예측하지 않고, 준비할 역량과 확인할 정보를 탐색합니다.",
    starter: "백엔드 직무를 준비하려면 지금 무엇을 확인해야 할까?",
    action: "준비 항목 초안에 가져오기",
  },
};

function workspaceContext(type) {
  const counts = {
    study: `수강 기록 ${state.registrations.length}개`,
    activity: `봉사 ${state.volunteers.length}건 · 활동 기록 ${state.experiences.length}건`,
    experience: `경험 ${state.experiences.length}건`,
    credential: `자격 ${state.certificates.length}건`,
    portfolio: `성과 ${state.works.length}건`,
    application: `경험 ${state.experiences.length}건 · 성과 ${state.works.length}건 · 자격 ${state.certificates.length}건`,
    career: `경험 ${state.experiences.length}건 · 자격 ${state.certificates.length}건 · 성과 ${state.works.length}건`,
  };
  return counts[type] || "기록 없음";
}

function workspaceAnswer(type) {
  const answers = {
    study: "학교 수강·성적 시스템이 기준입니다. 이 대화는 다음 학기 계획과 교육과정 탐색을 돕지만, 학사 기록이나 졸업 판정값을 바꾸지 않습니다.",
    activity: "봉사 활동은 1365 등에서 신청하고 학교에 등록·승인받는 흐름이 기준입니다. 이 대화는 부족한 활동을 찾고, 승인 완료한 기록을 정리하는 데만 도움을 줍니다.",
    experience: "경험은 역할, 문제, 실행, 결과 순서로 정리하면 이력과 포트폴리오에 재사용하기 쉽습니다. 기관명과 기간이 비어 있는 기록부터 보완해 보세요.",
    credential: "현재 학과 졸업인증과 채용 비교에서는 정보처리기사 확인이 필요합니다. Q-Net API로 종목과 접수·시험 일정을 가져와 준비 순서를 안내하고, 실제 원서접수는 Q-Net에서 진행합니다. 취득 후 학교 또는 채용에 등록·확인된 자격만 보유 자격에 추가해 주세요.",
    portfolio: "성과마다 문제, 담당 역할, 사용한 방법, 결과를 한 문단으로 먼저 정리해 보세요. 외부에 공개할 수 있는 링크나 증빙은 사용자가 직접 확인한 뒤 추가합니다.",
    application: "기록된 사실 중 지원 직무와 연결할 항목을 먼저 고릅니다. AI는 이력서와 자기소개서의 편집 초안만 돕고, 최종 문장과 사실 확인은 사용자가 직접 합니다.",
    career: "이 대화는 합격 가능성을 예측하지 않습니다. 현재 기록을 바탕으로 공고의 필수 요건, 우대 요건, 보완할 경험을 구분해 탐색할 수 있습니다.",
  };
  return answers[type] || "현재 기록을 바탕으로 다음 단계를 정리할 수 있습니다.";
}

function workspaceLayer() {
  const type = state.workspace_type;
  const meta = WORKSPACE_META[type];
  if (!meta) return "";
  const thread = state.workspaceThread.map((item) => `<div class="workspace-bubble ${item.role}"><small>${item.role === "user" ? "나의 요청" : "AI 정리"}</small><p>${esc(item.text)}</p></div>`).join("");
  const suggestions = state.suggested_actions.length
    ? `<section class="workspace-suggestions"><p class="kicker">제안된 다음 단계</p>${state.suggested_actions.map((item) => `<div><b>${esc(item)}</b><button type="button" class="ghost tiny" data-action="apply-workspace-draft">${meta.action}</button></div>`).join("")}</section>`
    : "";
  const qnetResult = type === "credential" && state.workspaceThread.length
    ? `<section class="workspace-qnet-result"><p class="kicker">필요 자격 · Q-Net 일정</p>${QNET_CREDENTIAL_HINTS.map((item) => `<div><b>${esc(item.name)}</b><p>${esc(item.reason)}<br />${esc(item.eligibility)} · ${esc(item.schedule)}</p><a class="external-link" href="https://www.q-net.or.kr/" target="_blank" rel="noopener noreferrer">Q-Net에서 원서접수 ↗</a></div>`).join("")}
      <details class="mock-integration-note" open><summary>목업 전용 · 이 결과를 위한 구현 연결점 <span>실제 사용자 화면에서는 제거</span></summary><div class="mock-integration-grid"><p><b>백엔드</b>Q-Net 공용 API에서 자격 종목, 응시자격, 접수·시험·합격발표 일정을 조회하고 캐시합니다.</p><p><b>RAG</b>학과 졸업인증·채용 비교의 부족 자격을 받아, 해당 종목의 일정과 준비 정보를 이 결과에 제시합니다.</p><p><b>개인 자격</b>Q-Net 개인 보유내역은 자동 조회하지 않습니다. 학교 또는 채용에 등록·확인된 자격만 직접 기록합니다.</p></div></details>
    </section>`
    : "";
  return `<div class="workspace-layer" role="dialog" aria-modal="true" aria-label="${esc(meta.title)}">
    <button type="button" class="workspace-backdrop" data-action="close-workspace" aria-label="작업 대화 닫기"></button>
    <section class="workspace-panel">
      <header><div><p class="kicker">${meta.eyebrow}</p><h2>${meta.title}</h2><p>${meta.description}</p></div><button type="button" class="chat-collapse" data-action="close-workspace" aria-label="닫기">×</button></header>
      <div class="workspace-context"><span>현재 읽은 기록</span><b>${esc(state.workspace_context || workspaceContext(type))}</b><small>대화 내용을 확인한 뒤 필요한 것만 직접 기록해 주세요.</small></div>
      <div class="workspace-thread">${thread || `<div class="workspace-empty"><b>무엇을 함께 정리할까요?</b><p>${meta.starter}</p></div>`}</div>
      ${qnetResult}
      ${suggestions}
      ${state.workspaceNotice ? `<p class="workspace-notice">${esc(state.workspaceNotice)}</p>` : ""}
      <form class="workspace-composer" data-action="workspace-submit"><input data-workspace-draft="true" value="${esc(state.conversation_draft)}" placeholder="${meta.starter}" /><button class="primary" type="submit">정리 요청</button></form>
    </section>
  </div>`;
}

function replyFor(kind) {
  const dept = currentDepartment();
  if (!dept || !dept.rules) {
    const text = !dept
      ? "학과 식별자가 비어 있어 공식 문서 범위를 정할 수 없습니다. 학과 이름으로 추정하지 않습니다."
      : `${dept.institution} ${dept.name}는 연결되어 있으나 공식 졸업 문서가 아직 없습니다. 기준을 추정하지 않습니다.`;
    return { status: "insufficient_evidence", text, sources: false };
  }
  if (kind === "eligibility" && !hasOfficialAudit()) {
    return {
      status: "not_applicable",
      text: state.account && state.account.year
        ? "이 학과의 최소 이수학점 문서는 있습니다. 이 목업의 취득학점 예시는 2024학번뿐이라, 다른 입학연도의 충족 여부는 판정하지 않습니다."
        : "이 학과의 최소 이수학점 문서는 있습니다. 입학연도가 없어 교육과정을 고르지 않았고, 충족 여부를 판정하지 않습니다.",
      sources: false,
    };
  }
  if (kind === "credits") {
    return {
      status: "cited",
      sources: true,
      doc: "credits",
      pages: [1, 2],
      text: "2024–2021 입학 단일전공 초안 기준 졸업 최소 이수학점은 120학점입니다. 교양 31, 전공 66(전공필수 일반 6, 전공기초필수 12, 전공선택 48), 자유선택 23입니다. 근거는 아래 2쪽이며, 같은 표가 1쪽부터 이어집니다. 학과 확인 전 초안입니다.",
    };
  }
  if (kind === "cert") {
    return {
      status: "cited",
      sources: true,
      doc: "cert",
      pages: [1, 3],
      text: "컴퓨터공학과 졸업인증제는 창의영역 택 1과 전공영역 택 1을 함께 채웁니다. 전공영역은 학과졸업인증제 I(자격/면허 또는 실무/실습) 또는 II(취업·창업 증빙) 중 하나이고, 계약학과·직장인 교과과정은 면제입니다. 이 대화는 충족 여부를 판정하지 않습니다. 규칙 엔진의 이번 학과 묶음은 확인 필요입니다.",
    };
  }
  if (kind === "eligibility") {
    return {
      status: "not_satisfied",
      sources: true,
      doc: "credits",
      pages: [1, 2],
      text: "규칙 엔진의 이번 감사는 미충족입니다. 학교 화면의 총 취득학점 88이 최소 120보다 적습니다. 학과 졸업인증 묶음은 창의영역(입력 TOEIC 850 ≥ 기타계열 500)은 채웠고, 전공영역 I·II는 확인 필요 또는 미충족이라 인증 전체는 확인 필요로 두었습니다. 수강 신청 내역으로 취득학점을 만들지 않았습니다.",
    };
  }
  return {
    status: "insufficient_evidence",
    sources: false,
    text: "교환학생 인정 학점 상한은 현재 교육과정 범위의 공식 문서에서 찾지 못했습니다. 상한을 추정하지 않습니다.",
  };
}

function isOfficialQuestion(text) {
  return /졸업|학점|교양|전공|교육과정|이수|인증|창의영역|전공영역|졸업작품|졸업시험|교환학생|인정학점|학사 규정|학칙/.test(text);
}

function screenWorkspaceType() {
  const types = {
    records: "study",
    activities: "activity",
    experiences: "experience",
    credentials: "credential",
    portfolio: "portfolio",
    jobs: "career",
  };
  return types[state.screen] || null;
}

function classify(text) {
  if (/교환|상한|인정학점/.test(text)) return "exchange";
  if (/인증|창의영역|전공영역|졸업작품|졸업시험|자격요건/.test(text)) return "cert";
  if (/졸업할|졸업 가능|졸업가능|할 수 있/.test(text)) return "eligibility";
  if (/학점|교양|전공|단일전공/.test(text)) return "credits";
  return "exchange";
}

function ask(kind, text) {
  const question = text || {
    credits: "2024학번 단일전공의 졸업 최소 이수학점은 얼마인가요?",
    cert: "컴퓨터공학과 졸업인증제는 어떻게 채우나요?",
    eligibility: "지금 졸업할 수 있나요?",
    exchange: "교환학생으로 인정되는 전공 학점 상한은 얼마인가요?",
  }[kind];
  state.draft = "";
  state.chatOpen = true;
  state.chat.push({ role: "user", text: question });
  state.chat.push({ role: "assistant", pending: true });
  render();
  window.setTimeout(() => {
    state.chat = state.chat.filter((item) => !item.pending);
    const answer = replyFor(kind || classify(question));
    state.chat.push({ role: "assistant", ...answer });
    render();
  }, 450);
}

function jobsScreen() {
  const requiredMet = [hasOfficialAudit(), state.experiences.length > 0, false].filter(Boolean).length;
  const result = state.jobPhase === "done" ? `
    <div class="verdict-top">
      <div>
        <div class="kicker">공고와 프로필</div>
        <h2 style="font-size:22px;margin:6px 0 0">필수 요건이 부족합니다</h2>
      </div>
      ${stamp("missing_required")}
    </div>
    <p class="disclaimer">상태 missing_required_requirements. 필수 3개 중 ${requiredMet}개 충족. 합격 예측이나 채용 순위가 아닙니다.</p>
    <div class="req"><div>${stamp(hasOfficialAudit() ? "met" : "unknown")}</div><div><b>학사 재학 또는 졸업예정</b><p>${hasOfficialAudit() ? "필수 · 컴퓨터공학과 2024학번 프로필과 맞음. 근거 academic profile." : "필수 · 정보 부족. 프로필에 재학이나 입학연도가 없습니다. 대학생이 아니어도 나머지 비교는 진행됩니다."}</p></div></div>
    <div class="req"><div>${stamp(state.experiences.length ? "met" : "missing")}</div><div><b>프로젝트 또는 실무 경험</b><p>${state.experiences.length ? "필수 · 경험에 적은 기록으로 충족." : "필수 · 경험 기록이 없습니다."}</p></div></div>
    <div class="req"><div>${stamp("missing")}</div><div><b>정보처리기사</b><p>필수 · 보유 자격증에 없습니다. TOEIC은 이 요건의 대체 그룹이 아닙니다.</p></div></div>
    <div class="req"><div>${stamp("not_evaluated")}</div><div><b>Kubernetes 경험</b><p>우대 · 자동 비교 제외. 이유 manual_confirmation_required. 프로필에 확인 가능한 근거 식별자가 없습니다.</p></div></div>
    <div class="req"><div>${stamp("unknown")}</div><div><b>석사 학위</b><p>우대 · 정보 부족. 이유 profile_data_missing. 같은 안내 목록에 모아 보여 줍니다.</p></div></div>` : "";

  return `<header class="page-head">
      <div>
        <p class="kicker">채용 공고 · 2차</p>
        <h1>채용 적합도</h1>
        <p class="lede">공고 요건과 프로필을 항목별로 비교합니다. 점수로 합격을 예측하지 않습니다.</p>
      </div>
    </header>
    <div class="jobs">
      <section class="card">
        <h2>공고</h2>
        <p><b>백엔드 엔지니어</b></p>
        <p class="disclaimer">합성회사 한빛클라우드 · 정규직 · 게시 2026-09-01 · 마감 2026-10-15</p>
        <p class="disclaimer">원문 URL은 목업용 예시입니다.</p>
        <form data-action="analyze" style="margin-top:14px">
          <input id="job-url" aria-label="공고 URL" value="https://example.com/jobs/backend-2026" style="width:100%;border:1px solid var(--line);border-radius:12px;padding:11px 12px;background:var(--paper)" />
          <button class="primary" type="submit" style="margin-top:10px;width:100%">${state.jobPhase === "loading" ? "비교 중" : "요건 추출 후 비교"}</button>
        </form>
        <p class="disclaimer">지원 상태와 피드백 추천은 3차 MVP의 JobApplication 범위입니다. 이 목업에는 화면을 두지 않았습니다.</p>
      </section>
      <section class="card">
        ${state.jobPhase === "idle" ? `<h2>비교 결과</h2><p class="disclaimer">버튼을 누르면 합성 공고의 필수·우대 요건과 프로필 근거를 나란히 보여 줍니다.</p>` : ""}
        ${state.jobPhase === "loading" ? `<div class="pending" aria-label="비교 중"><i></i><i></i><i></i></div>` : ""}
        ${result}
      </section>
    </div>`;
}

function scopeScreen() {
  return `<header class="page-head">
      <div>
        <p class="kicker">관리 범위</p>
        <h1>적용 범위</h1>
        <p class="lede">이 관리자 계정은 경동대학교 컴퓨터공학과 범위만 다룹니다.</p>
      </div>
    </header>
    <section class="card">
      <div class="stack">
        <div class="row-card"><span class="tag">institution</span><div><b>경동대학교</b><p>국가 KR · 공식 URL은 학교 데이터 등록 시 입력</p></div><span class="stamp ok">범위 안</span></div>
        <div class="row-card"><span class="tag">department</span><div><b>컴퓨터공학과</b><p>학과 코드는 초안에서 비어 있습니다.</p></div><span class="stamp ok">범위 안</span></div>
        <div class="row-card"><span class="tag">curriculum</span><div><b>입학연도 묶음 4개</b><p>2026–2025, 2024–2021, 2020, 2019–2018. 학생 정민서에게는 2024–2021 단일전공이 적용됩니다.</p></div><span class="stamp warn">초안</span></div>
      </div>
    </section>
    <div class="callout">학교 공통 규칙 묶음은 아직 초안 JSON에 없습니다. 학과 졸업인증과 교육과정 학점 규칙이 연결되어 있습니다.</div>`;
}

function rulesScreen() {
  return `<header class="page-head">
      <div>
        <p class="kicker">교육과정 규칙</p>
        <h1>학점 규칙 초안</h1>
        <p class="lede">학점 초안은 교육과정 묶음, 졸업인증 초안은 학과 묶음입니다.</p>
      </div>
    </header>
    <div class="banner">PDF 텍스트를 옮긴 초안입니다. 규칙 엔진에 넣기 전에 학과 또는 학사 담당자 확인이 필요합니다.</div>
    <section class="card table-wrap">
      <table class="data">
        <thead><tr><th>입학연도</th><th>이수 경로</th><th>교양</th><th>전공</th><th class="num">자유</th><th class="num">졸업</th><th>쪽</th></tr></thead>
        <tbody>
          ${BANDS.map((band) => `<tr class="${band.applied ? "is-hit" : ""}">
            <td>${esc(band.years)}</td>
            <td>${esc(band.track)}${band.applied ? " · 현재 학생" : ""}${band.note ? `<div style="color:var(--muted);font-size:12px">${esc(band.note)}</div>` : ""}</td>
            <td>${esc(band.liberal)}</td>
            <td>${esc(band.major)}</td>
            <td class="num">${esc(band.free)}</td>
            <td class="num">${esc(band.total)}</td>
            <td>${esc(band.page)}</td>
          </tr>`).join("")}
        </tbody>
      </table>
    </section>
    <section class="card table-wrap">
      <h2>학과 졸업인증 초안</h2>
      <p class="disclaimer">kduniv_computer_science_graduation_certification.json · 졸업인증요건 PDF</p>
      <table class="data">
        <thead><tr><th>규칙</th><th>쪽</th></tr></thead>
        <tbody>
          ${DEPT_RULES.map((line) => `<tr><td><b>${esc(line.title)}</b><div style="color:var(--muted);font-size:12px;margin-top:3px">${esc(line.group)}</div></td><td>${line.page}</td></tr>`).join("")}
        </tbody>
      </table>
    </section>`;
}

function homeScreen() {
  const dept = currentDepartment();
  const official = hasOfficialAudit();
  const kicker = official
    ? `${esc(dept.institution)} ${esc(dept.name)} · ${esc(state.account.year)}학번`
    : "한눈에";
  const name = state.account ? esc(state.account.name) : "학생";
  const plannedCredits = state.registrations.filter((row) => row.term === CURRENT_TERM).reduce((sum, row) => sum + Number(row.credits), 0);
  const volunteerHours = state.volunteers.reduce((sum, row) => sum + Number(row.hours), 0);
  return `<header class="page-head home-page-head">
      <div class="head-lead">
        <p class="kicker">${kicker}</p>
        <h1>${name}님, 오늘 무엇을 정리해볼까요?</h1>
        <p class="lede">기록과 판정은 본문에서 확인하고, 정리·탐색·계획은 오른쪽 AI 대화에서 시작해요.</p>
      </div>
      <p class="home-updated">목업 데이터 기준</p>
    </header>
    <section class="home-hero">
      <div class="home-hero-copy">
        <p class="home-hero-label"><span class="home-hero-dot"></span>MY UNIVERSITY PATH</p>
        <h2>기록을 쌓고, 다음 선택을<br />차분하게 이어가세요.</h2>
        <p>수강 계획, 학교 승인 활동, 경험과 성과를 한곳에서 확인합니다. 궁금한 점은 오른쪽 AI 도우미에게 자연어로 물어보세요.</p>
      </div>
    </section>
    <div class="home-grid home-grid-compact">
      <section class="card home-focus-card"><div class="home-card-top"><span class="home-link-kicker">ACADEMIC BASIS</span><span class="home-card-icon">⌁</span></div><h2>학사 기준</h2><p class="disclaimer">${official ? "연결한 학교·학과·입학연도에 맞는 적용 기준을 확인합니다." : "학교·학과·입학연도를 연결하면 적용 기준을 확인할 수 있어요."}</p><button type="button" class="ghost" data-action="nav" data-screen="graduation">기준 보기 <span>→</span></button></section>
      <section class="card home-activity-card"><div class="home-card-top"><span class="home-link-kicker">MY RECORDS</span><span class="home-card-icon soft">⌁</span></div><h2>이번 학기와 활동</h2><p class="disclaimer">수강 계획 ${state.registrations.filter((row) => row.term === CURRENT_TERM).length}과목 · ${plannedCredits}학점<br />학교 승인 봉사 ${volunteerHours}시간 · 경험 ${state.experiences.length}건</p><button type="button" class="ghost" data-action="nav" data-screen="records">기록 확인하기 <span>→</span></button></section>
      <section class="card home-activity-card"><div class="home-card-top"><span class="home-link-kicker">OFFICIAL SOURCES</span><span class="home-card-icon soft">⌁</span></div><h2>공식 문서</h2><p class="disclaimer">규정 원문과 페이지 근거를 확인합니다.</p><button type="button" class="ghost" data-action="nav" data-screen="sources">문서 보기 <span>→</span></button></section>
      <section class="card home-activity-card"><div class="home-card-top"><span class="home-link-kicker">PERSONAL GROWTH</span><span class="home-card-icon soft">⌁</span></div><h2>성과와 진로</h2><p class="disclaimer">성과 ${state.works.length}건 · 보유 자격 ${state.certificates.length}건</p><button type="button" class="ghost" data-action="nav" data-screen="portfolio">성과 보기 <span>→</span></button></section>
    </div>`;
}

function settingsScreen() {
  const profile = profileMeta();
  const account = state.account;
  return `<header class="page-head">
      <div class="head-lead">
        <p class="kicker">계정</p>
        <h1>설정</h1>
        <p class="lede">계정, 학과 연결, 화면 배치를 둡니다. 인증 공급자는 아직 정하지 않았습니다.</p>
      </div>
    </header>
    <div class="settings-grid">
      <section class="card">
        <h2>계정</h2>
        <p><b>${esc(profile.name)}</b></p>
        <p class="disclaimer">${state.role === "admin" || !account ? "합성 관리자 계정입니다. 관리자 가입 화면은 없습니다." : `${esc(account.email)} · ${account.year ? `${esc(account.year)}학번` : "입학연도 없음"}`}</p>
        <p class="disclaimer">${esc(profile.detail)}</p>
      </section>
      <section class="card">
        <h2>화면</h2>
        ${state.role === "student" ? `<div class="seg" role="group" aria-label="AI 대화">
          <button type="button" data-action="toggle-chat" aria-pressed="${state.chatOpen}">AI 대화 ${state.chatOpen ? "열림" : "닫힘"}</button>
        </div>
        <p class="disclaimer" style="margin-top:8px">오른쪽 패널에서 기록 정리·계획·탐색을 진행하고, 졸업·학사 질문은 공식 문서 근거와 함께 확인합니다. 졸업 여부는 Rule Engine이 판정합니다.</p>` : `<p class="disclaimer">관리자 화면에는 AI 대화 패널이 없습니다.</p>`}
      </section>
      <section class="card">
        <h2>역할</h2>
        <div class="seg" role="group" aria-label="역할">
          <button type="button" data-action="role" data-role="student" aria-pressed="${state.role === "student"}">이용자</button>
          <button type="button" data-action="role" data-role="admin" aria-pressed="${state.role === "admin"}">학교 관리자</button>
        </div>
        <p class="disclaimer" style="margin-top:8px">목업에서 이용자와 학교 관리자 화면을 바꿉니다.</p>
      </section>
      <section class="card">
        <h2>세션</h2>
        <button type="button" class="ghost logout" data-action="logout">로그아웃</button>
        <p class="disclaimer" style="margin-top:8px">목업 세션만 지웁니다. 서버 계정은 없습니다.</p>
      </section>
    </div>
    ${state.role === "student" && state.account ? affiliationCard() : ""}`;
}

function docsScreen() {
  return `<header class="page-head">
      <div>
        <p class="kicker">근거 문서</p>
        <h1>공식 문서</h1>
        <p class="lede">검색 근거로 쓰는 문서와 적용 범위입니다. 청크와 임베딩은 이 목업에 없습니다.</p>
      </div>
    </header>
    <section class="card sources">
      ${sourceCard()}
      <div class="meta-row">
        <span class="chip">범위 경동대학교</span>
        <span class="chip">컴퓨터공학과</span>
        <span class="chip">입학연도별 교육과정</span>
        <span class="chip">document_type graduation_credit</span>
      </div>
    </section>
    <section class="card sources">
      ${sourceCard([1], false, "cert")}
      <div class="meta-row">
        <span class="chip">범위 경동대학교</span>
        <span class="chip">컴퓨터공학과</span>
        <span class="chip">학과 졸업인증</span>
        <span class="chip">document_type graduation_certification</span>
      </div>
    </section>`;
}

function studyScreen(activePane = "records") {
  const dept = currentDepartment();
  const official = hasOfficialAudit();
  const kicker = official
    ? `${esc(dept.institution)} ${esc(dept.name)} · ${esc(state.account.year)}학번`
    : "학사";
  const lede = official
    ? "학교 수강·성적 시스템을 먼저 확인해 주세요. 여기서는 다음 수강 계획과 함께 확인할 항목을 정리할 수 있습니다."
    : !dept
      ? (currentInstitution()
        ? "학과 식별자가 없으면 졸업 여부를 판정하지 않습니다. 활동·자격과 채용 적합도는 그대로 쓸 수 있고, 수강 기록도 직접 넣을 수 있습니다."
        : "학교 없이 써도 됩니다. 활동·자격과 채용 적합도는 그대로 쓸 수 있고, 수강 기록도 직접 넣을 수 있습니다. 졸업 판정은 학과와 입학연도가 연결된 뒤에만 합니다.")
      : dept.rules
        ? "학과 식별자는 연결되어 있습니다. 입학연도를 적으면 그 해의 교육과정으로 감사를 엽니다. 재학 중이 아니면 비워 둡니다."
        : "학과 식별자는 연결되어 있습니다. 이 학과에는 공식 감사 예시가 없어 졸업 여부를 판정하지 않습니다.";
  const headVerdict = official
    ? `<div class="head-verdict">
        <div class="score">88<span>/ 120</span></div>
        ${stamp("not_satisfied")}
      </div>`
    : "";
  const isAudit = activePane === "audit";
  const pane = isAudit ? auditScreen() : recordsScreen();
  return `<header class="page-head">
      <div class="head-lead">
        <p class="kicker">${kicker}</p>
        <h1>${isAudit ? "졸업 요건" : "수강 관리"}</h1>
        <div class="seg" role="group" aria-label="수강과 졸업">
          <button type="button" data-action="study-pane" data-pane="records" aria-pressed="${!isAudit}">수강</button>
          <button type="button" data-action="study-pane" data-pane="audit" aria-pressed="${isAudit}">졸업</button>
        </div>
        <p class="lede">${lede}</p>
      </div>
      ${headVerdict}
    </header>
    ${isAudit ? `<div class="rule-engine-note"><b>Rule Engine 판정</b><span>학교 시스템에 아직 반영되지 않은 항목이 있다면 먼저 학교에서 승인·등록 상태를 확인해 주세요.</span><button type="button" class="ghost tiny" data-action="open-official" data-q="eligibility">근거 보기</button></div>` : ""}
    ${official ? "" : affiliationCard()}
    <div class="pane">${pane}</div>`;
}

function main() {
  if (state.screen === "settings") return settingsScreen();
  if (state.role === "admin") {
    if (state.screen === "rules") return rulesScreen();
    if (state.screen === "docs") return docsScreen();
    return scopeScreen();
  }
  if (state.screen === "home") return homeScreen();
  if (state.screen === "sources") return docsScreen();
  if (state.screen === "activities") return activitiesScreen("activities");
  if (state.screen === "experiences") return activitiesScreen("experiences");
  if (state.screen === "credentials") return activitiesScreen("credentials");
  if (state.screen === "portfolio") return activitiesScreen("portfolio");
  if (state.screen === "records") return studyScreen("records");
  if (state.screen === "graduation") return studyScreen("audit");
  if (state.screen === "jobs") return jobsScreen();
  return studyScreen("records");
}

function displayName() {
  if (state.role === "admin") return "합성 관리자 · 컴퓨터공학과";
  const name = state.account ? state.account.name : "정민서";
  const dept = currentDepartment();
  const inst = currentInstitution();
  if (dept && hasOfficialAudit()) return `${name} · ${state.account.year}학번`;
  if (dept) return `${name} · ${dept.name}`;
  if (state.account && state.account.departmentNote) return `${name} · ${state.account.departmentNote}`;
  if (inst) return `${name} · ${inst.name}`;
  return name;
}

function sampleAccount() {
  return {
    name: "정민서", email: "minseo@example.com", year: "2024",
    institutionId: "inst-kd", departmentId: "dept-cs", departmentNote: "",
  };
}

function clearPersonal() {
  state.registrations = [];
  state.volunteers = [];
  state.experiences = [];
  state.certificates = [];
  state.works = [];
}

function restoreSampleStudent() {
  state.registrations = REGISTRATIONS.map((row) => ({ ...row }));
  state.volunteers = [{ id: "v1", title: "교내 봉사", hours: 30 }];
  state.experiences = [
    { id: "e1", type: "동아리", title: "축제 운영", organization: "합성 동아리", started: "2025-05-01", ended: "2025-05-03" },
    { id: "e2", type: "아르바이트", title: "서점 근무", organization: "합성 서점", started: "2026-03-01", ended: "" },
  ];
  state.certificates = [{ id: "c1", name: "TOEIC", detail: "850", earned: "2025-11-02" }];
  state.works = [{ id: "w1", title: "졸업 프로젝트", kind: "포트폴리오" }];
}

function enterStudent(account) {
  const next = account || sampleAccount();
  state.account = next;
  if (hasOfficialAudit()) restoreSampleStudent();
  else clearPersonal();
  state.account = next;
  state.linked = hasOfficialAudit();
  state.session = "student";
  state.role = "student";
  state.studyPane = "records";
  state.screen = next.institutionId || next.departmentId ? "home" : "activities";
  state.viewer = null;
  state.authError = "";
}

function enterAdmin() {
  state.session = "admin";
  state.role = "admin";
  state.screen = "scope";
  state.account = null;
  state.viewer = null;
  state.authError = "";
}

function authScreen() {
  const draft = state.authDraft;
  const login = state.authPane === "login";
  const field = (label, name, type, extra = "") => `<label class="${extra}">${label}<input type="${type}" data-store="authDraft" data-field="${name}" value="${esc(draft[name])}" /></label>`;
  const pickedSchool = findInstitution(draft.institutionId);
  const pickedDept = findDepartment(draft.departmentId);
  const deptBlock = !pickedSchool
    ? ""
    : `<div class="wide" data-dept-block>${pickedSchool.departments.length
      ? `<label class="wide">학과 검색<input data-search="auth-dept" data-store="authDraft" data-field="deptQuery" value="${esc(draft.deptQuery)}" placeholder="학과 이름" /></label>
        <div class="search-results wide" data-results="auth-dept">${searchResultHtml("auth-dept")}</div>
        ${pickedDept ? `<p class="chosen wide">선택 · ${esc(pickedDept.name)}</p>` : `<p class="disclaimer wide">찾지 못하면 비운 채로 가입합니다.</p>`}`
      : `<p class="disclaimer wide">이 학교는 등록된 학과가 없습니다. 학과는 비운 채로 가입합니다.</p>`}</div>`;
  const form = login
    ? `<form class="auth-form" data-action="login">
        ${field("이메일", "email", "email", "wide")}
        ${field("비밀번호", "password", "password", "wide")}
        <button class="primary wide" type="submit">로그인</button>
      </form>`
    : `<form class="auth-form" data-action="signup">
        ${field("이름", "name", "text", "wide")}
        ${field("이메일", "email", "email", "wide")}
        ${field("비밀번호", "password", "password")}
        ${field("비밀번호 확인", "confirm", "password")}
        <label class="wide">학교 검색<input data-search="auth-school" data-store="authDraft" data-field="schoolQuery" value="${esc(draft.schoolQuery)}" placeholder="학교 이름" /></label>
        <div class="search-results wide" data-results="auth-school">${searchResultHtml("auth-school")}</div>
        ${pickedSchool ? `<p class="chosen wide" data-school-chosen>선택 · ${esc(pickedSchool.name)}</p>` : `<p class="disclaimer wide">검색 결과에서 고릅니다. 없으면 칸을 비우고 가입합니다.</p>`}
        ${deptBlock}
        <button class="primary wide" type="submit">가입하고 들어가기</button>
      </form>`;
  return `<main class="auth">
      <section class="auth-panel">
        <div class="auth-card">
          <div class="brand auth-brand">
            <div class="mark" aria-hidden="true">
              <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
                <path d="M3.5 4.2h4.4c.6 0 1.2.4 1.6.9.4-.5 1-.9 1.6-.9h4.4V13.8h-4.4c-.6 0-1.2.3-1.6.7-.4-.4-1-.7-1.6-.7H3.5V4.2Z" stroke="#f7f5f2" stroke-width="1.3" stroke-linejoin="round"/>
              </svg>
            </div>
            <div>
              <div class="brand-name">UniversityPath</div>
              <div class="brand-sub">화면 목업</div>
            </div>
          </div>
          <p class="kicker">YOUR UNIVERSITY PATH</p>
          <h1>나의 대학생활 경로를 관리하세요.</h1>
          <p class="lede">학업, 활동, 진로 기록을 한 곳에서 이어갑니다.</p>
          <div class="seg" role="group" aria-label="계정 화면">
            <button type="button" data-action="auth-pane" data-pane="login" aria-pressed="${login}">로그인</button>
            <button type="button" data-action="auth-pane" data-pane="signup" aria-pressed="${!login}">회원가입</button>
          </div>
          <h2>${login ? "로그인" : "회원가입"}</h2>
          ${form}
          ${state.authError ? `<p class="disclaimer" style="color:var(--bad)">${esc(state.authError)}</p>` : ""}
          <div class="auth-samples">
            <p>칸을 채우지 않고 목업 화면만 보려면</p>
            <button type="button" class="ghost" data-action="enter-sample" data-as="student">샘플 학생</button>
            <button type="button" class="ghost" data-action="enter-sample" data-as="admin">샘플 관리자</button>
          </div>
        </div>
      </section>
    </main>`;
}

function render() {
  if (state.screen === "ask") state.screen = "study";
  const app = document.getElementById("app");
  app.classList.toggle("has-chat", Boolean(state.session && state.role === "student" && state.chatOpen));
  app.innerHTML = state.session ? shell(main()) : authScreen();
  const thread = document.querySelector(".chat-thread");
  if (thread) thread.scrollTop = thread.scrollHeight;
}

document.body.addEventListener("click", (event) => {
  const target = event.target.closest("[data-action]");
  if (!target) return;
  if (target.closest("form") && (target === target.closest("form") || target.type === "submit")) return;
  const action = target.dataset.action;
  if (action === "pick-auth-school") {
    const inst = findInstitution(target.dataset.id);
    if (!inst) return;
    state.authDraft.institutionId = inst.id;
    state.authDraft.schoolQuery = inst.name;
    state.authDraft.departmentId = "";
    state.authDraft.deptQuery = "";
    render();
  } else if (action === "pick-auth-dept") {
    const dept = findDepartment(target.dataset.id);
    if (!dept || dept.institutionId !== state.authDraft.institutionId) return;
    state.authDraft.departmentId = dept.id;
    state.authDraft.deptQuery = dept.name;
    render();
  } else if (action === "pick-link-school") {
    const inst = findInstitution(target.dataset.id);
    if (!inst || !state.account) return;
    state.account = { ...state.account, institutionId: inst.id, departmentId: null };
    state.linkDraft = { schoolQuery: inst.name, deptQuery: "" };
    state.linked = hasOfficialAudit();
    render();
  } else if (action === "pick-link-dept") {
    const dept = findDepartment(target.dataset.id);
    if (!dept || !state.account || dept.institutionId !== state.account.institutionId) return;
    state.account = { ...state.account, departmentId: dept.id };
    state.linkDraft.deptQuery = dept.name;
    state.linked = hasOfficialAudit();
    render();
  } else if (action === "auth-pane") {
    state.authPane = target.dataset.pane;
    state.authError = "";
    render();
  } else if (action === "enter-sample") {
    if (target.dataset.as === "admin") enterAdmin();
    else enterStudent(null);
    render();
  } else if (action === "logout") {
    state.session = null;
    state.viewer = null;
    state.authError = "";
    state.authPane = "login";
    render();
  } else if (action === "toggle-chat") {
    state.chatOpen = !state.chatOpen;
    render();
  } else if (action === "open-official") {
    ask(target.dataset.q || "credits");
  } else if (action === "open-workspace") {
    const type = target.dataset.workspace;
    if (!WORKSPACE_META[type]) return;
    state.workspace_type = type;
    state.workspace_context = workspaceContext(type);
    state.suggested_actions = [];
    state.workspaceNotice = "";
    state.chatOpen = true;
    state.chat.push({ role: "assistant", workspace: type, text: WORKSPACE_META[type].description });
    render();
  } else if (action === "clear-ai-context") {
    state.workspace_type = null;
    state.workspace_context = null;
    state.suggested_actions = [];
    render();
  } else if (action === "close-workspace") {
    state.workspace_type = null;
    state.workspace_context = null;
    render();
  } else if (action === "apply-workspace-draft") {
    const type = state.workspace_type;
    if (type === "study") state.regDraft.title = "AI와 정리한 수강 계획";
    if (type === "activity") state.volunteerDraft.title = "AI와 정리한 활동";
    if (type === "experience") state.experienceDraft.title = "AI와 정리한 경험";
    if (type === "credential") state.certificateDraft.name = "AI와 정리한 준비 자격";
    if (type === "portfolio") state.workDraft.title = "AI와 정리한 포트폴리오 항목";
    if (type === "application") state.applicationNotice = "AI 제안은 지원 문서의 편집 초안입니다. 사실과 표현을 직접 확인한 뒤 지원처별 문서로 완성해 주세요.";
    state.workspaceNotice = "초안을 가져왔습니다. 내용을 확인한 뒤 필요한 것만 직접 기록해 주세요.";
    render();
  } else if (action === "fill-ai-prompt") {
    state.draft = target.dataset.prompt || "";
    render();
  } else if (action === "portfolio-pane") {
    const pane = target.dataset.pane;
    if (["records", "showcase", "application"].includes(pane)) state.portfolioPane = pane;
    render();
  } else if (action === "toggle-side") {
    state.sideOpen = !state.sideOpen;
    if (state.sideOpen) state.sideWidth = clampSideWidth(state.sideWidth);
    render();
  } else if (action === "nav") {
    state.screen = target.dataset.screen === "ask" ? "study" : target.dataset.screen;
    state.workspace_type = null;
    state.workspace_context = null;
    state.suggested_actions = [];
    state.viewer = null;
    render();
  } else if (action === "open-doc") {
    const cited = (target.dataset.cited || "").split(",").map(Number).filter((n) => n >= 1 && n <= 3);
    state.viewer = { page: Number(target.dataset.page) || 1, cited, doc: target.dataset.doc || "credits" };
    render();
  } else if (action === "close-doc") {
    state.viewer = null;
    render();
  } else if (action === "doc-page") {
    const next = Number(target.dataset.page);
    if (!state.viewer || target.disabled || next < 1 || next > 3) return;
    state.viewer = { ...state.viewer, page: next };
    render();
  } else if (action === "role") {
    const stay = state.screen === "settings";
    state.role = target.dataset.role;
    if (state.role === "student" && !state.account) enterStudent(null);
    state.screen = stay ? "settings" : (state.role === "student" ? "home" : "scope");
    render();
  } else if (action === "rule") {
    state.openRule = state.openRule === target.dataset.id ? null : target.dataset.id;
    render();
  } else if (action === "study-pane") {
    state.studyPane = target.dataset.pane;
    state.screen = state.studyPane === "audit" ? "graduation" : "records";
    render();
  } else if (action === "toggle-mock-tools") {
    state.mockToolsOpen = !state.mockToolsOpen;
    render();
  } else if (action === "audit-preview") {
    state.auditPreview = target.dataset.preview === "kookmin" ? "kookmin" : "kd";
    state.auditFilter = "institution";
    state.openRule = null;
    state.mockToolsOpen = false;
    render();
  } else if (action === "audit-filter") {
    state.auditFilter = target.dataset.filter;
    render();
  } else if (action === "audit-set") {
    const id = target.dataset.id;
    const next = `set:${id}`;
    if (state.auditFilter === next) {
      const set = RULE_SETS.find((item) => item.id === id);
      state.auditFilter = set ? set.scope : "all";
    } else {
      state.auditFilter = next;
    }
    render();
  } else if (action === "reg-filter") {
    state.regFilter = target.dataset.filter;
    render();
  } else if (action === "remove-reg") {
    state.registrations = state.registrations.filter((row) => row.id !== target.dataset.id);
    render();
  } else if (action === "remove-volunteer") {
    state.volunteers = state.volunteers.filter((row) => row.id !== target.dataset.id);
    render();
  } else if (action === "remove-experience") {
    state.experiences = state.experiences.filter((row) => row.id !== target.dataset.id);
    render();
  } else if (action === "remove-certificate") {
    state.certificates = state.certificates.filter((row) => row.id !== target.dataset.id);
    render();
  } else if (action === "remove-work") {
    state.works = state.works.filter((row) => row.id !== target.dataset.id);
    render();
  } else if (action === "ask") {
    ask(target.dataset.q);
  }
});

function rememberField(event) {
  const store = event.target.dataset.store;
  const field = event.target.dataset.field;
  if (store && field && state[store]) state[store][field] = event.target.value;
}

document.body.addEventListener("input", (event) => {
  if (event.target.id === "composer") state.draft = event.target.value;
  if (event.target.dataset.workspaceDraft !== undefined) state.conversation_draft = event.target.value;
  rememberField(event);
  const kind = event.target.dataset.search;
  if (!kind) return;
  if (kind === "auth-school") {
    state.authDraft.institutionId = "";
    state.authDraft.departmentId = "";
    state.authDraft.deptQuery = "";
    const chosen = document.querySelector("[data-school-chosen]");
    const block = document.querySelector("[data-dept-block]");
    if (chosen) chosen.hidden = true;
    if (block) block.hidden = true;
  }
  if (kind === "auth-dept") state.authDraft.departmentId = "";
  if (kind === "link-school" && state.account) {
    state.account = { ...state.account, institutionId: null, departmentId: null };
  }
  const box = document.querySelector(`[data-results="${kind}"]`);
  if (box) box.innerHTML = searchResultHtml(kind);
});

document.body.addEventListener("change", rememberField);

document.body.addEventListener("submit", (event) => {
  const form = event.target.closest("form");
  if (!form) return;
  event.preventDefault();
  if (form.dataset.action === "login") {
    const email = state.authDraft.email.trim();
    const password = state.authDraft.password;
    if (!email || !password) {
      state.authError = "이메일과 비밀번호를 입력해 주세요. 목업이라 값은 확인하지 않습니다.";
      render();
      return;
    }
    enterStudent(null);
    render();
  } else if (form.dataset.action === "signup") {
    const draft = state.authDraft;
    const name = draft.name.trim();
    const email = draft.email.trim();
    if (!name || !email || !draft.password) {
      state.authError = "이름, 이메일, 비밀번호를 입력해 주세요.";
      render();
      return;
    }
    if (draft.password !== draft.confirm) {
      state.authError = "비밀번호 확인이 비밀번호와 다릅니다.";
      render();
      return;
    }
    if (draft.schoolQuery.trim() && !draft.institutionId) {
      state.authError = "학교는 검색 결과에서 골라 주세요. 없으면 검색칸을 비우세요.";
      render();
      return;
    }
    if (draft.deptQuery.trim() && !draft.departmentId) {
      state.authError = "학과는 검색 결과에서 골라 주세요. 없으면 검색칸을 비우세요.";
      render();
      return;
    }
    const inst = findInstitution(draft.institutionId);
    const dept = inst && inst.departments.some((item) => item.id === draft.departmentId)
      ? draft.departmentId
      : null;
    enterStudent({
      name, email, year: "",
      institutionId: inst ? inst.id : null,
      departmentId: dept,
      departmentNote: "",
    });
    render();
  } else if (form.dataset.action === "save-year") {
    if (!state.account) return;
    state.account = { ...state.account, year: state.yearDraft.year };
    state.linked = hasOfficialAudit();
    render();
  } else if (form.dataset.action === "save-note") {
    if (!state.account) return;
    state.account = { ...state.account, departmentNote: state.noteDraft.text.trim() };
    state.noteDraft.text = "";
    render();
  } else if (form.dataset.action === "ask-submit") {
    const text = state.draft.trim();
    if (!text) return;
    ask(classify(text), text);
  } else if (form.dataset.action === "unified-ai-submit") {
    const text = state.draft.trim();
    if (!text) return;
    if (isOfficialQuestion(text)) {
      ask(classify(text), text);
      return;
    }
    const type = screenWorkspaceType();
    if (!type) {
      state.chat.push({ role: "user", text });
      state.chat.push({ role: "assistant", text: "현재 화면의 전문 기록 맥락이 없어, 목표와 상황을 조금 더 알려주시면 정리 방법과 확인할 정보를 제안할게요." });
      state.draft = "";
      render();
      return;
    }
    state.workspace_type = type;
    state.workspace_context = workspaceContext(type);
    state.chat.push({ role: "user", text, workspace: type });
    state.chat.push({ role: "assistant", workspace: type, text: workspaceAnswer(type) });
    state.suggested_actions = [
      type === "study" ? "공식 교육과정과 다음 학기 개설 과목 확인" : type === "application" ? "지원 직무와 연결할 성과·경험 선택" : "현재 기록의 빈 정보와 증빙 자료 확인",
      type === "career" ? "관심 공고의 필수·우대 요건을 분리해 확인" : "확인한 내용을 기록 초안으로 가져오기",
    ];
    state.draft = "";
    state.workspaceNotice = "제안을 확인한 뒤 필요한 것만 직접 기록해 주세요.";
    render();
  } else if (form.dataset.action === "workspace-submit") {
    const text = state.conversation_draft.trim();
    const type = state.workspace_type;
    if (!text || !type) return;
    state.workspaceThread.push({ role: "user", text });
    state.workspaceThread.push({ role: "assistant", text: workspaceAnswer(type) });
    state.suggested_actions = [
      type === "study" ? "공식 교육과정과 다음 학기 개설 과목 확인" : type === "application" ? "지원 직무와 연결할 성과·경험 선택" : "현재 기록의 빈 정보와 증빙 자료 확인",
      type === "career" ? "관심 공고의 필수·우대 요건을 분리해 확인" : "확인한 내용을 기록 초안으로 가져오기",
    ];
    state.conversation_draft = "";
    state.workspaceNotice = "제안을 확인한 뒤 필요한 것만 직접 기록해 주세요.";
    render();
  } else if (form.dataset.action === "add-registration") {
    const term = state.regDraft.term.trim();
    const title = state.regDraft.title.trim();
    const credits = Number(state.regDraft.credits);
    if (!term || !title || !Number.isFinite(credits) || credits <= 0) {
      state.regError = "학기, 과목명, 학점을 입력해 주세요.";
      render();
      return;
    }
    state.registrations.unshift({
      id: `r${Date.now()}`,
      term,
      title,
      category: state.regDraft.category || "전선",
      credits,
      section: state.regDraft.section.trim(),
    });
    state.regDraft.title = "";
    state.regDraft.section = "";
    state.regError = "";
    const addedNow = term === CURRENT_TERM;
    if (state.regFilter === "current" && !addedNow) state.regFilter = "past";
    if (state.regFilter === "past" && addedNow) state.regFilter = "current";
    render();
  } else if (form.dataset.action === "add-volunteer") {
    const title = state.volunteerDraft.title.trim();
    const hours = Number(state.volunteerDraft.hours);
    if (!title || !Number.isFinite(hours) || hours <= 0) {
      state.volunteerError = "내용과 시간을 입력해 주세요.";
      render();
      return;
    }
    state.volunteers.unshift({ id: `v${Date.now()}`, title, hours });
    state.volunteerDraft = { title: "", hours: "" };
    state.volunteerError = "";
    render();
  } else if (form.dataset.action === "add-experience") {
    const title = state.experienceDraft.title.trim();
    if (!title) {
      state.experienceError = "제목을 입력해 주세요.";
      render();
      return;
    }
    state.experiences.unshift({
      id: `e${Date.now()}`,
      type: state.experienceDraft.type || "기타",
      title,
      organization: state.experienceDraft.organization.trim(),
      started: state.experienceDraft.started,
      ended: state.experienceDraft.ended,
    });
    state.experienceDraft = { type: state.experienceDraft.type, title: "", organization: "", started: "", ended: "" };
    state.experienceError = "";
    render();
  } else if (form.dataset.action === "add-certificate") {
    const name = state.certificateDraft.name.trim();
    if (!name) {
      state.certificateError = "자격 이름을 입력해 주세요.";
      render();
      return;
    }
    state.certificates.unshift({
      id: `c${Date.now()}`,
      name,
      detail: state.certificateDraft.detail.trim(),
      earned: state.certificateDraft.earned,
    });
    state.certificateDraft = { name: "", detail: "", earned: "" };
    state.certificateError = "";
    render();
  } else if (form.dataset.action === "add-work") {
    const title = state.workDraft.title.trim();
    if (!title) {
      state.workError = "제목을 입력해 주세요.";
      render();
      return;
    }
    state.works.unshift({
      id: `w${Date.now()}`,
      title,
      kind: state.workDraft.kind || "프로젝트",
      role: state.workDraft.role.trim(),
      period: state.workDraft.period.trim(),
      result: state.workDraft.result.trim(),
      url: state.workDraft.url.trim(),
    });
    state.workDraft = { title: "", kind: state.workDraft.kind, role: "", period: "", result: "", url: "" };
    state.workError = "";
    render();
  } else if (form.dataset.action === "analyze") {
    state.jobPhase = "loading";
    render();
    window.setTimeout(() => {
      state.jobPhase = "done";
      render();
    }, 450);
  }
});

let panelDrag = null;

function endPanelDrag(clientX) {
  if (!panelDrag) return;
  const { kind, startX, startW, moved } = panelDrag;
  panelDrag = null;
  document.body.classList.remove("is-resizing-chat", "is-resizing-side");
  if (!moved) return;
  if (kind === "chat") {
    const raw = startW + (startX - clientX);
    if (raw < CHAT_WIDTH.collapse + 20) {
      state.chatWidth = clampChatWidth(startW);
      state.chatOpen = false;
      render();
      return;
    }
    state.chatWidth = clampChatWidth(raw);
    applyChatWidth(state.chatWidth);
    return;
  }
  const raw = startW + (clientX - startX);
  if (raw < SIDE_WIDTH.collapse + 20) {
    if (startW >= SIDE_WIDTH.min) state.sideWidth = clampSideWidth(startW);
    state.sideOpen = false;
    render();
    return;
  }
  state.sideOpen = true;
  state.sideWidth = clampSideWidth(raw);
  render();
}

document.addEventListener("pointerdown", (event) => {
  const handle = event.target.closest("[data-resize]");
  if (!handle) return;
  const kind = handle.dataset.resize;
  if (kind !== "chat" && kind !== "side") return;
  event.preventDefault();
  const startW = kind === "chat" ? state.chatWidth : sideWidthNow();
  panelDrag = { kind, startX: event.clientX, startW, moved: false };
  document.body.classList.add(kind === "chat" ? "is-resizing-chat" : "is-resizing-side");
});

document.addEventListener("pointermove", (event) => {
  if (!panelDrag) return;
  if (Math.abs(event.clientX - panelDrag.startX) > 2) panelDrag.moved = true;
  if (panelDrag.kind === "chat") {
    applyChatWidth(panelDrag.startW + (panelDrag.startX - event.clientX));
    return;
  }
  applySideWidth(panelDrag.startW + (event.clientX - panelDrag.startX));
});

document.addEventListener("pointerup", (event) => {
  endPanelDrag(event.clientX);
});

document.addEventListener("pointercancel", (event) => {
  endPanelDrag(event.clientX);
});

document.addEventListener("dblclick", (event) => {
  const handle = event.target.closest("[data-resize]");
  if (!handle) return;
  if (handle.dataset.resize === "chat") {
    state.chatWidth = CHAT_WIDTH.def;
    applyChatWidth(state.chatWidth);
    return;
  }
  if (handle.dataset.resize === "side") {
    state.sideOpen = true;
    state.sideWidth = SIDE_WIDTH.def;
    render();
  }
});

render();

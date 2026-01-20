-- 철인 마일리지 관리 시스템 데이터베이스 스키마
-- Supabase PostgreSQL DDL

-- iron_members 테이블: 멤버 기본 정보 저장
CREATE TABLE IF NOT EXISTS iron_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    sports TEXT NOT NULL, -- 종목들 (쉼표로 구분: 예: "수영,러닝,사이클")
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- iron_member_records 테이블: 멤버별 목표 마일리지 기록 저장
CREATE TABLE IF NOT EXISTS iron_member_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES iron_members(id) ON DELETE CASCADE,
    year INTEGER NOT NULL,
    month INTEGER NOT NULL CHECK (month >= 1 AND month <= 12),
    sport TEXT NOT NULL CHECK (sport IN ('수영', '러닝', '사이클')),
    target_mileage NUMERIC(10, 2) NOT NULL CHECK (target_mileage >= 0), -- 목표 마일리지 (미터 단위)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT iron_member_records_unique UNIQUE (member_id, year, month, sport)
);

-- iron_mileages 테이블: 마일리지 기록 저장 (누적 방식 - 같은 년도/월/종목에 여러 레코드 저장 가능)
CREATE TABLE IF NOT EXISTS iron_mileages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES iron_members(id) ON DELETE CASCADE,
    member_name TEXT NOT NULL, -- 조회 성능을 위한 중복 저장
    sport TEXT NOT NULL CHECK (sport IN ('수영', '러닝', '사이클')),
    year INTEGER NOT NULL,
    month INTEGER NOT NULL CHECK (month >= 1 AND month <= 12),
    distance NUMERIC(10, 2) NOT NULL CHECK (distance >= 0), -- 거리 (미터 단위, 각 기록마다 별도 저장)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 기존 테이블 마이그레이션 (기존 데이터가 있는 경우)
DO $$ 
BEGIN
    -- 기존 iron_members 테이블에 year, month, target_mileage가 있는 경우
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'iron_members' AND column_name = 'year'
    ) THEN
        -- 기존 데이터를 새 구조로 마이그레이션
        INSERT INTO iron_member_records (member_id, year, month, sport, target_mileage, created_at, updated_at)
        SELECT 
            id as member_id,
            year,
            month,
            unnest(string_to_array(sports, ',')) as sport,
            target_mileage,
            created_at,
            updated_at
        FROM iron_members
        WHERE year IS NOT NULL AND month IS NOT NULL AND target_mileage IS NOT NULL
        ON CONFLICT DO NOTHING;
        
        -- 기존 컬럼 제거
        ALTER TABLE iron_members DROP COLUMN IF EXISTS year;
        ALTER TABLE iron_members DROP COLUMN IF EXISTS month;
        ALTER TABLE iron_members DROP COLUMN IF EXISTS target_mileage;
        
        -- 기존 제약 제거
        IF EXISTS (
            SELECT 1 FROM pg_constraint 
            WHERE conname = 'iron_members_name_key'
        ) THEN
            ALTER TABLE iron_members DROP CONSTRAINT iron_members_name_key;
        END IF;
        
        IF EXISTS (
            SELECT 1 FROM pg_constraint 
            WHERE conname = 'iron_members_name_year_month_sports_unique'
        ) THEN
            ALTER TABLE iron_members DROP CONSTRAINT iron_members_name_year_month_sports_unique;
        END IF;
    END IF;
END $$;

-- 인덱스 생성 (조회 성능 향상)
CREATE INDEX IF NOT EXISTS idx_iron_members_name ON iron_members(name);

CREATE INDEX IF NOT EXISTS idx_iron_member_records_member_id ON iron_member_records(member_id);
CREATE INDEX IF NOT EXISTS idx_iron_member_records_year_month ON iron_member_records(year, month);
CREATE INDEX IF NOT EXISTS idx_iron_member_records_member_year_month_sport ON iron_member_records(member_id, year, month, sport);

CREATE INDEX IF NOT EXISTS idx_iron_mileages_member_id ON iron_mileages(member_id);
CREATE INDEX IF NOT EXISTS idx_iron_mileages_member_name ON iron_mileages(member_name);
CREATE INDEX IF NOT EXISTS idx_iron_mileages_year_month ON iron_mileages(year, month);
CREATE INDEX IF NOT EXISTS idx_iron_mileages_created_at ON iron_mileages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_iron_mileages_member_year_month ON iron_mileages(member_id, year, month);

-- updated_at 자동 업데이트 트리거 함수
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- iron_members 테이블의 updated_at 자동 업데이트 트리거
CREATE TRIGGER update_iron_members_updated_at
    BEFORE UPDATE ON iron_members
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- iron_member_records 테이블의 updated_at 자동 업데이트 트리거
CREATE TRIGGER update_iron_member_records_updated_at
    BEFORE UPDATE ON iron_member_records
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- RLS (Row Level Security) 정책 설정 (선택사항)
-- Supabase에서 공개 접근을 허용하려면 다음 정책을 활성화하세요

-- ALTER TABLE iron_members ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE iron_member_records ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE iron_mileages ENABLE ROW LEVEL SECURITY;

-- 공개 읽기/쓰기 정책 (개발 환경용)
-- CREATE POLICY "Allow public read access on iron_members" ON iron_members FOR SELECT USING (true);
-- CREATE POLICY "Allow public insert access on iron_members" ON iron_members FOR INSERT WITH CHECK (true);
-- CREATE POLICY "Allow public update access on iron_members" ON iron_members FOR UPDATE USING (true);
-- CREATE POLICY "Allow public delete access on iron_members" ON iron_members FOR DELETE USING (true);

-- CREATE POLICY "Allow public read access on iron_member_records" ON iron_member_records FOR SELECT USING (true);
-- CREATE POLICY "Allow public insert access on iron_member_records" ON iron_member_records FOR INSERT WITH CHECK (true);
-- CREATE POLICY "Allow public update access on iron_member_records" ON iron_member_records FOR UPDATE USING (true);
-- CREATE POLICY "Allow public delete access on iron_member_records" ON iron_member_records FOR DELETE USING (true);

-- CREATE POLICY "Allow public read access on iron_mileages" ON iron_mileages FOR SELECT USING (true);
-- CREATE POLICY "Allow public insert access on iron_mileages" ON iron_mileages FOR INSERT WITH CHECK (true);
-- CREATE POLICY "Allow public update access on iron_mileages" ON iron_mileages FOR UPDATE USING (true);
-- CREATE POLICY "Allow public delete access on iron_mileages" ON iron_mileages FOR DELETE USING (true);

-- 주석 추가
COMMENT ON TABLE iron_members IS '멤버 기본 정보 저장';
COMMENT ON TABLE iron_member_records IS '멤버별 목표 마일리지 기록 저장';
COMMENT ON TABLE iron_mileages IS '멤버별 마일리지 기록 저장 (누적 방식 - 같은 년도/월/종목에 여러 레코드 저장 가능)';

COMMENT ON COLUMN iron_members.name IS '멤버 이름';
COMMENT ON COLUMN iron_members.sports IS '참여 종목들 (쉼표로 구분: 예: "수영,러닝,사이클")';

COMMENT ON COLUMN iron_member_records.member_id IS '멤버 ID (외래키)';
COMMENT ON COLUMN iron_member_records.year IS '목표 설정 년도';
COMMENT ON COLUMN iron_member_records.month IS '목표 설정 월 (1-12)';
COMMENT ON COLUMN iron_member_records.sport IS '종목 (수영, 러닝, 사이클)';
COMMENT ON COLUMN iron_member_records.target_mileage IS '목표 마일리지 (미터 단위)';
COMMENT ON CONSTRAINT iron_member_records_unique ON iron_member_records IS '동일한 멤버, 년도, 월, 종목 조합은 유일해야 함';

COMMENT ON COLUMN iron_mileages.member_id IS '멤버 ID (외래키)';
COMMENT ON COLUMN iron_mileages.member_name IS '멤버 이름 (조회 성능을 위한 중복 저장)';
COMMENT ON COLUMN iron_mileages.sport IS '종목 (수영, 러닝, 사이클)';
COMMENT ON COLUMN iron_mileages.year IS '기록 년도';
COMMENT ON COLUMN iron_mileages.month IS '기록 월 (1-12)';
COMMENT ON COLUMN iron_mileages.distance IS '거리 (미터 단위)';
COMMENT ON COLUMN iron_mileages.created_at IS '기록 생성 시간';

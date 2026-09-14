-- Migration 0007: outlet legal / billing identity for quotation documents
-- (legal entity, registration + VAT numbers, registered office, banking details shown on the PDF).
-- Idempotent: safe to re-run.
alter table public.outlets
  add column if not exists legal_name              text,        -- e.g. "Izandra Trading 36 (Pty) Ltd"
  add column if not exists trading_as              text,        -- e.g. "Sparkling Auto Care Centre Menlyn"
  add column if not exists company_registration_no text,        -- e.g. "2006/024689/07"
  add column if not exists vat_number              text,        -- e.g. "4310233384"
  add column if not exists registered_office       text,        -- e.g. "PO Box 238, Potchefstroom, North West, 2531, South Africa"
  add column if not exists bank_details            jsonb;       -- {financial_institution, account_name, branch, branch_code, account_number, account_type}

-- Demo values for the seeded outlets (only where nothing has been captured yet).
update public.outlets set
  legal_name = 'Izandra Trading 36 (Pty) Ltd',
  trading_as = 'Sparkling Auto Care Centre ' || replace(name, 'Sparkling ', ''),
  company_registration_no = '2006/024689/07',
  vat_number = '4310233384',
  registered_office = 'PO Box 238, Potchefstroom, North West, 2531, South Africa',
  bank_details = jsonb_build_object(
    'financial_institution', 'First National Bank',
    'account_name', 'Izandra Trading 36 (Pty) Ltd',
    'branch', replace(name, 'Sparkling ', ''),
    'branch_code', '250655',
    'account_number', '63041170711',
    'account_type', 'Gold Business Account')
where legal_name is null and code in ('SAN', 'ROS', 'CEN');

CREATE OR REPLACE FUNCTION "public"."set_row_bin_index" ()  RETURNS TRIGGER
  VOLATILE
AS $body$
BEGIN
	SELECT find_bin_index(NEW.chromosome, NEW.location_start, NEW.location_end) INTO NEW.bin_index;
RETURN NEW;
END
$body$ LANGUAGE plpgsql 

\timing on

create table FeatureLocation as
select cast('gene' as varchar(4)) as feature_type,
       id as feature_source_id,
       cast(chromosome as varchar(2)) as chromosome,
       start_min,
       end_max,
       cast(is_reversed as numeric(1)) as is_reversed
from Gene
union
select cast('snp' as varchar(4)) as feature_type,
       source_id as feature_source_id,
       cast (case chromosome
               when 'mitochondrion' then 'M'
               else chromosome
             end as varchar(2)) as chromosome,
       start_min,
       end_max,
       cast(null as numeric(1)) as is_reversed
from Snp;

create index featloc_ix on FeatureLocation(feature_type, chromosome, start_min, end_max, is_reversed, feature_source_id);

create index featid_ix on FeatureLocation(feature_source_id, feature_type, chromosome, start_min, end_max, is_reversed);

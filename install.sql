-- Bu SQL dosyası raporlama sistemi için tasarlanan tabloyu veritabanına kurar.
-- claimed_by ve resolved_by kolonları yetkili oyuncunun license değerini saklar.
-- Görüntüleme sırasında players tablosu ile JOIN yapılarak isim gösterilir.

CREATE TABLE IF NOT EXISTS `qb_reports` (
    `id`               INT(11)      NOT NULL AUTO_INCREMENT,
    `category`         VARCHAR(64)  NOT NULL,
    `category_label`   VARCHAR(128) NOT NULL DEFAULT '',
    `description`      TEXT         NOT NULL,
    `reporter_id`      INT          NOT NULL,
    `reporter_name`    VARCHAR(128) NOT NULL DEFAULT 'Unknown',
    `target_id`        INT              NULL DEFAULT NULL,
    `target_name`      VARCHAR(128)     NULL DEFAULT NULL,
    `status`           ENUM('open','claimed','resolved') NOT NULL DEFAULT 'open',
    `claimed_by`       VARCHAR(128)     NULL DEFAULT NULL COMMENT 'Yetkili license identifier (players.license ile JOIN)',
    `resolved_by`      VARCHAR(128)     NULL DEFAULT NULL COMMENT 'Yetkili license identifier (players.license ile JOIN)',
    `claimed_at`       DATETIME         NULL DEFAULT NULL,
    `resolved_at`      DATETIME         NULL DEFAULT NULL,
    `resolve_duration` INT              NULL DEFAULT NULL COMMENT 'saniye cinsinden çözüm süresi',
    `created_at`       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_status`      (`status`),
    INDEX `idx_resolved_by` (`resolved_by`(64)),
    INDEX `idx_created_at`  (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

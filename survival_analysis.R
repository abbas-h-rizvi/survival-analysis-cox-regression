# Survival Analysis & Cox Regression in R
# Portfolio adaptation of collaborative MSc Actuarial Science coursework
# Bayes Business School
#
# This script presents a cleaned, recruiter-facing version of the survival
# analysis. The original coursework was completed collaboratively; sole
# authorship of the original submission is not claimed here.
#
# Data note:
# The original analysis used "midata.xlsx". The dataset is not bundled here.
# Place the workbook in the repository root before running this script.

# -------------------------------------------------------------------------
# 0. Setup
# -------------------------------------------------------------------------

required_packages <- c("survival", "survminer", "readxl", "dplyr")

missing_packages <- required_packages[
  !sapply(required_packages, requireNamespace, quietly = TRUE)
]

if (length(missing_packages) > 0) {
  stop(
    "Please install the following packages before running this script: ",
    paste(missing_packages, collapse = ", ")
  )
}

library(survival)
library(survminer)
library(readxl)
library(dplyr)

dir.create("figures", showWarnings = FALSE)

data_file <- "midata.xlsx"

if (!file.exists(data_file)) {
  stop(
    "Data file 'midata.xlsx' was not found. ",
    "Place the workbook in the repository root before running this script."
  )
}

# -------------------------------------------------------------------------
# 1. Load and prepare data
# -------------------------------------------------------------------------

midata_raw <- read_excel(
  data_file,
  sheet = "Sheet3",
  skip = 1
)

colnames(midata_raw) <- c(
  "ID",
  "AdmDate",
  "FollowUpDate",
  "LengthOfStay",
  "FollowUpTime",
  "Status",
  "Age",
  "Gender",
  "BMI"
)

midata <- midata_raw %>%
  mutate(
    time = as.numeric(FollowUpTime),
    event = if_else(Status == "Dead", 1L, 0L),
    Gender = factor(Gender, levels = c("Male", "Female"))
  )

cat("\n--- Event counts by gender ---\n")
print(table(
  midata$Gender,
  midata$event,
  dnn = c("Gender", "Event (1=Dead, 0=Alive)")
))

# -------------------------------------------------------------------------
# 2. Kaplan-Meier survival analysis by gender
# -------------------------------------------------------------------------

km_gender <- survfit(
  Surv(time, event) ~ Gender,
  data = midata
)

cat("\n--- Kaplan-Meier estimates by gender ---\n")
print(km_gender)

logrank_gender <- survdiff(
  Surv(time, event) ~ Gender,
  data = midata
)

cat("\n--- Log-rank test ---\n")
print(logrank_gender)

km_plot <- ggsurvplot(
  km_gender,
  data = midata,
  pval = TRUE,
  conf.int = TRUE,
  risk.table = TRUE,
  legend.labs = c("Male", "Female"),
  xlab = "Time (days)",
  ylab = "Survival Probability S(t)",
  title = "Kaplan-Meier Survival Curves by Gender",
  ggtheme = theme_bw()
)

png(
  "figures/kaplan_meier_by_gender.png",
  width = 1400,
  height = 1000,
  res = 150
)
print(km_plot)
dev.off()

# -------------------------------------------------------------------------
# 3. Cox proportional hazards model: Age + BMI
# -------------------------------------------------------------------------

cox_age_bmi <- coxph(
  Surv(time, event) ~ Age + BMI,
  data = midata
)

cat("\n--- Cox model: Age + BMI ---\n")
print(summary(cox_age_bmi))

hazard_ratios <- exp(coef(cox_age_bmi))

cat("\n--- Hazard ratios ---\n")
print(hazard_ratios)

# Adjusted survival curves at representative ages, BMI held at sample mean
new_data_age <- data.frame(
  Age = c(50, 60, 70, 80),
  BMI = rep(mean(midata$BMI, na.rm = TRUE), 4)
)

age_plot <- ggsurvplot(
  survfit(cox_age_bmi, newdata = new_data_age),
  data = midata,
  conf.int = FALSE,
  legend.labs = c("Age 50", "Age 60", "Age 70", "Age 80"),
  xlab = "Time (days)",
  ylab = "Adjusted Survival Probability",
  title = "Cox-Adjusted Survival by Age (BMI held at mean)",
  ggtheme = theme_bw()
)

png(
  "figures/cox_adjusted_survival_by_age.png",
  width = 1200,
  height = 800,
  res = 150
)
print(age_plot)
dev.off()

# Likelihood-ratio comparison with a null model
cox_null <- coxph(
  Surv(time, event) ~ 1,
  data = midata
)

lr_stat <- -2 * (
  as.numeric(logLik(cox_null)) -
  as.numeric(logLik(cox_age_bmi))
)

lr_p_value <- pchisq(
  lr_stat,
  df = 2,
  lower.tail = FALSE
)

cat(
  sprintf(
    "\nLikelihood-ratio test vs null: statistic = %.3f, df = 2, p = %.4g\n",
    lr_stat,
    lr_p_value
  )
)

# -------------------------------------------------------------------------
# 4. Interaction model: do Age and BMI effects differ by gender?
# -------------------------------------------------------------------------

cox_main <- coxph(
  Surv(time, event) ~ Gender + Age + BMI,
  data = midata
)

cox_interaction <- coxph(
  Surv(time, event) ~ Gender + Age + BMI +
    Gender:Age + Gender:BMI,
  data = midata
)

cat("\n--- Main-effects model ---\n")
print(summary(cox_main))

cat("\n--- Interaction model ---\n")
print(summary(cox_interaction))

lr_interaction <- -2 * (
  as.numeric(logLik(cox_main)) -
  as.numeric(logLik(cox_interaction))
)

interaction_p_value <- pchisq(
  lr_interaction,
  df = 2,
  lower.tail = FALSE
)

cat(
  sprintf(
    "\nInteraction likelihood-ratio test: statistic = %.3f, df = 2, p = %.4g\n",
    lr_interaction,
    interaction_p_value
  )
)

# Separate models by gender as a descriptive sensitivity check
cox_male <- coxph(
  Surv(time, event) ~ Age + BMI,
  data = filter(midata, Gender == "Male")
)

cox_female <- coxph(
  Surv(time, event) ~ Age + BMI,
  data = filter(midata, Gender == "Female")
)

cat("\n--- Male model coefficients ---\n")
print(summary(cox_male)$coefficients)

cat("\n--- Female model coefficients ---\n")
print(summary(cox_female)$coefficients)

# Adjusted survival curves across representative BMI values at age 65
new_data_gender <- expand.grid(
  Gender = factor(
    c("Male", "Female"),
    levels = c("Male", "Female")
  ),
  Age = 65,
  BMI = c(22, 27, 32)
)

interaction_plot <- ggsurvplot(
  survfit(cox_interaction, newdata = new_data_gender),
  data = midata,
  conf.int = FALSE,
  legend.labs = paste(
    new_data_gender$Gender,
    "BMI",
    new_data_gender$BMI
  ),
  xlab = "Time (days)",
  ylab = "Adjusted Survival Probability",
  title = "Cox Interaction Model: Gender × BMI at Age 65",
  ggtheme = theme_bw()
)

png(
  "figures/cox_interaction_gender_bmi.png",
  width = 1300,
  height = 850,
  res = 150
)
print(interaction_plot)
dev.off()

# -------------------------------------------------------------------------
# 5. Compact results summary
# -------------------------------------------------------------------------

cox_summary <- summary(cox_age_bmi)

results <- data.frame(
  variable = rownames(cox_summary$coefficients),
  coefficient = cox_summary$coefficients[, "coef"],
  hazard_ratio = cox_summary$coefficients[, "exp(coef)"],
  p_value = cox_summary$coefficients[, "Pr(>|z|)"],
  row.names = NULL
)

cat("\n--- Compact Cox model results ---\n")
print(results)

cat("\n--- Interaction test p-value ---\n")
print(interaction_p_value)
